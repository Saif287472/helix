import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:helix_local_groups/application/lan_lobby_client.dart';
import 'package:helix_local_groups/application/lan_lobby_discovery.dart';
import 'package:helix_local_groups/application/lan_lobby_election.dart';
import 'package:helix_local_groups/application/lan_lobby_handoff.dart';
import 'package:helix_local_groups/application/lan_lobby_server.dart';
import 'package:helix_local_groups/domain/lobby_constants.dart';
import 'package:helix_local_groups/domain/lobby_state.dart';
import 'package:helix_local_groups/platform/multicast_lock.dart';
import 'package:helix_local_groups/platform/multicast_lock_android.dart';
import 'package:helix_local_groups/platform/multicast_lock_stub.dart';

enum _LobbyRole { idle, discovering, hosting, joining, joined, leaving }

/// Public API for the LAN Lobby system.
class LanLobbyService {
  LanLobbyService({MulticastLock? multicastLock})
      : _lock = multicastLock ??
            (Platform.isAndroid
                ? MulticastLockAndroid(kLobbyMulticastChannel)
                : MulticastLockStub());

  final MulticastLock     _lock;
  final _discovery        = LanLobbyDiscovery();
  final _uuid             = const Uuid();

  LanLobbyServer? _server;
  LanLobbyClient? _client;

  _LobbyRole _role = _LobbyRole.idle;

  String _localFp  = '';
  String _name     = '';
  String _suffix   = '';

  LobbyState? _state;

  // Bounded duplicate-message suppression set
  final _seenMsgIds = <String>[];

  final _stateCtrl   = StreamController<LobbyState?>.broadcast();
  final _messageCtrl = StreamController<LobbyMessage>.broadcast();

  Timer? _announceTimer;
  StreamSubscription<dynamic>? _discoverySub;
  StreamSubscription<dynamic>? _serverJoinSub;
  StreamSubscription<dynamic>? _serverFrameSub;
  StreamSubscription<dynamic>? _serverDisconnectSub;
  StreamSubscription<dynamic>? _clientFrameSub;
  StreamSubscription<dynamic>? _clientDisconnectSub;

  bool _disposed = false;
  int  _lifecycleGeneration = 0;
  bool _electionRunning     = false;
  Future<void>? _leaveFuture;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Stream<LobbyState?> get stateStream   => _stateCtrl.stream;
  Stream<LobbyMessage> get messageStream => _messageCtrl.stream;

  LobbyState? get currentState => _state;
  bool get isHost => _role == _LobbyRole.hosting;
  bool get isActive => _role == _LobbyRole.hosting || _role == _LobbyRole.joined;

  /// Join (or create) the LAN lobby. Safe to call multiple times; subsequent
  /// calls while already active are ignored.
  Future<void> join({
    required String localFp,
    required String name,
    required String suffix,
  }) async {
    if (_disposed) return;
    if (_role != _LobbyRole.idle) return;
    _leaveFuture = null;

    _localFp = localFp;
    _name    = name;
    _suffix  = suffix;
    _role    = _LobbyRole.discovering;

    try {
      await _lock.acquire();
    } catch (_) {}

    try {
      await _discovery.open();
    } catch (e) {
      _role = _LobbyRole.idle;
      try { await _lock.release(); } catch (_) {}
      rethrow;
    }

    _discoverySub = _discovery.incoming.listen(_onUdpFrame, cancelOnError: false);

    // Send an immediate discovery request and wait kLobbyDiscoveryWindow.
    _discovery.sendDiscoveryRequest(localFp);

    // Wait for a response. If we get one, _onUdpFrame will handle it and
    // change our role. If not, we self-elect as host.
    await Future.delayed(kLobbyDiscoveryWindow);

    if (_disposed) return;
    if (_role == _LobbyRole.discovering) {
      // No host found — run the election procedure.
      await _runElection(survivors: [localFp]);
    }
  }

  /// Leave the lobby. Triggers graceful handoff if we are the host.
  Future<void> leave() => _leaveFuture ??= _doLeave();

  /// Send a chat message to the lobby.
  Future<void> sendMessage(String text) async {
    final state = _state;
    if (state == null || !isActive) return;
    final frame = {
      'v':     kLobbyProtocolVersion,
      't':     kFtMsg,
      'sid':   state.sessionId,
      'gen':   state.generation,
      'msgId': _uuid.v4(),
      'fp':    _localFp,
      'name':  _name,
      'text':  text,
      'ts':    DateTime.now().millisecondsSinceEpoch,
    };
    if (isHost) {
      _deliverMessage(frame);
      _server?.broadcastFrame(frame);
    } else {
      _client?.send(frame);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await leave();
    await _stateCtrl.close();
    await _messageCtrl.close();
  }

  // ---------------------------------------------------------------------------
  // UDP frame handler
  // ---------------------------------------------------------------------------

  void _onUdpFrame(LobbyDatagram datagram) {
    try {
      _onUdpFrameUnsafe(datagram);
    } catch (_) {}
  }

  void _onUdpFrameUnsafe(LobbyDatagram datagram) {
    final frame = datagram.frame;
    final type  = frame['t'] as String?;

    if (type == kFtAnnounce) {
      _handleAnnounce(frame, datagram.sender, datagram.senderPort);
    } else if (type == kFtDiscoveryRequest && isHost) {
      // Respond immediately to discovery requests
      final state = _state;
      if (state == null) return;
      final nonce = frame['nonce'] as String?;
      _discovery.sendDiscoveryResponse(
        target:        datagram.sender,
        targetPort:    datagram.senderPort,
        sid:           state.sessionId,
        gen:           state.generation,
        hostFp:        _localFp,
        tcpPort:       _server!.port,
        memberCount:   state.memberCount,
        replyToNonce:  nonce ?? '',
      );
    }
  }

  void _handleAnnounce(Map<String, dynamic> frame, InternetAddress sender, int senderPort) {
    final incomingGen    = (frame['gen'] as num?)?.toInt() ?? -1;
    final incomingHostFp = frame['hostFp'] as String? ?? '';
    final tcpPort        = (frame['port'] as num?)?.toInt() ?? 0;
    if (incomingGen < 0 || incomingHostFp.isEmpty || tcpPort <= 0) return;

    final localState = _state;

    // If we're still discovering, join the announced host.
    if (_role == _LobbyRole.discovering) {
      _connectToHost(sender.address, tcpPort, frame);
      return;
    }

    // If we're hosting or in election, apply conflict resolution.
    if (_role == _LobbyRole.hosting || _role == _LobbyRole.discovering) {
      final localGen = localState?.generation ?? 0;
      if (localLosesConflict(
        localGen:       localGen,
        localFp:        _localFp,
        incomingGen:    incomingGen,
        incomingHostFp: incomingHostFp,
      )) {
        _surrenderHostTo(sender.address, tcpPort, frame);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Become host
  // ---------------------------------------------------------------------------

  Future<void> _becomeHost({
    required String sid,
    required int    gen,
  }) async {
    final server = LanLobbyServer();
    try {
      await server.open(sid: sid, gen: gen);
    } catch (_) {
      await server.close().catchError((_) {});
      _role = _LobbyRole.discovering;
      rethrow;
    }

    if (_disposed) {
      await server.close();
      return;
    }

    _server = server;
    _role = _LobbyRole.hosting;

    final selfMember = LobbyMember(fp: _localFp, name: _name, suffix: _suffix);
    _state = LobbyState(
      sessionId:         sid,
      members:           [selfMember],
      localFp:           _localFp,
      hostFp:            _localFp,
      generation:        gen,
      membershipVersion: 0,
    );
    _emitState();

    _serverJoinSub = server.joinRequests.listen(_onClientJoin, cancelOnError: false);
    _serverFrameSub = server.clientFrames.listen(_onClientFrame, cancelOnError: false);
    _serverDisconnectSub = server.disconnections.listen(_onClientDisconnect, cancelOnError: false);

    _startAnnouncing();
  }

  void _startAnnouncing() {
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(kLobbyBroadcastInterval, (_) {
      final state = _state;
      if (state == null || _server == null) return;
      _discovery.sendAnnounce(
        sid:         state.sessionId,
        gen:         state.generation,
        hostFp:      _localFp,
        tcpPort:     _server!.port,
        memberCount: state.memberCount,
      );
    });
    // Send immediately
    final state = _state;
    if (state != null && _server != null) {
      _discovery.sendAnnounce(
        sid:         state.sessionId,
        gen:         state.generation,
        hostFp:      _localFp,
        tcpPort:     _server!.port,
        memberCount: state.memberCount,
      );
    }
  }

  void _stopAnnouncing() {
    _announceTimer?.cancel();
    _announceTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Host: handle joining clients
  // ---------------------------------------------------------------------------

  void _onClientJoin(({Socket socket, Map<String, dynamic> frame}) event) {
    final frame   = event.frame;
    final fpVal   = frame['fp'];
    final fp      = fpVal is String ? fpVal : '';
    final nameVal = frame['name'];
    final name    = nameVal is String ? nameVal : (fp.isNotEmpty ? fp.substring(0, fp.length.clamp(0, 8)) : '');
    final suffixVal = frame['suffix'];
    final suffix  = suffixVal is String ? suffixVal : '';
    if (fp.isEmpty || fp == _localFp) return;

    final state = _state;
    if (state == null || _role != _LobbyRole.hosting) return;

    // Reject members from a stale session/generation
    final incomingSid = frame['sid'];
    final incomingGen = frame['gen'] is num ? (frame['gen'] as num).toInt() : -1;
    if (incomingSid != state.sessionId || incomingGen != state.generation) {
      _server?.sendToFp(fp, {
        'v': kLobbyProtocolVersion, 't': kFtError,
        'code': 'stale_gen', 'msg': 'Session or generation mismatch',
      });
      return;
    }

    final newMember = LobbyMember(fp: fp, name: name, suffix: suffix);
    final members   = [...state.members.where((m) => m.fp != fp), newMember];
    final newMv     = state.membershipVersion + 1;
    final newState  = state.copyWith(members: members, membershipVersion: newMv);
    _state = newState;
    _emitState();

    // Send JOINED to the new member
    _server?.sendToFp(fp, {
      'v':       kLobbyProtocolVersion,
      't':       kFtJoined,
      'sid':     newState.sessionId,
      'gen':     newState.generation,
      'hostFp':  _localFp,
      'mv':      newMv,
      'members': membersToJson(members),
    });

    // Broadcast updated member list to everyone else
    _server?.broadcastFrame({
      'v':       kLobbyProtocolVersion,
      't':       kFtMemberUpdate,
      'sid':     newState.sessionId,
      'gen':     newState.generation,
      'mv':      newMv,
      'members': membersToJson(members),
    }, exceptFp: fp);
  }

  void _onClientFrame(({String fp, Map<String, dynamic> frame}) event) {
    try {
      _onClientFrameUnsafe(event);
    } catch (_) {}
  }

  void _onClientFrameUnsafe(({String fp, Map<String, dynamic> frame}) event) {
    final frame = event.frame;
    final state = _state;
    if (state == null || _role != _LobbyRole.hosting) return;

    if (frame['sid'] != state.sessionId ||
        frame['gen'] != state.generation) {
      return;
    }

    final claimedFp = frame['fp'];
    if (claimedFp != null && claimedFp != event.fp) {
      return;
    }

    final type  = frame['t'] as String?;
    if (type == kFtMsg) {
      // Relay to all other clients and deliver locally
      _deliverMessage(frame);
      _server?.broadcastFrame(frame, exceptFp: event.fp);
    } else if (type == kFtPing) {
      _server?.sendToFp(event.fp, {
        'v': kLobbyProtocolVersion, 't': kFtPong,
        'sid': state.sessionId, 'gen': state.generation,
      });
    } else if (type == kFtHostXferReady) {
      // Forwarded to handoff logic via server.clientFrames stream — no action here.
    }
  }

  void _onClientDisconnect(String fp) {
    final state = _state;
    if (state == null) return;
    final members = state.members.where((m) => m.fp != fp).toList();
    final newMv   = state.membershipVersion + 1;
    _state = state.copyWith(members: members, membershipVersion: newMv);
    _emitState();
    _server?.broadcastFrame({
      'v':       kLobbyProtocolVersion,
      't':       kFtMemberUpdate,
      'sid':     _state!.sessionId,
      'gen':     _state!.generation,
      'mv':      newMv,
      'members': membersToJson(members),
    });
  }

  // ---------------------------------------------------------------------------
  // Join existing host (client role)
  // ---------------------------------------------------------------------------

  void _connectToHost(String hostIp, int tcpPort, Map<String, dynamic> announceFrame) {
    if (_role != _LobbyRole.discovering && _role != _LobbyRole.hosting) return;
    _role = _LobbyRole.joining;

    final sid = announceFrame['sid'] as String? ?? '';
    final gen = (announceFrame['gen'] as num?)?.toInt() ?? 0;

    _doConnectAsClient(hostIp: hostIp, tcpPort: tcpPort, sid: sid, gen: gen).ignore();
  }

  Future<void> _doConnectAsClient({
    required String hostIp,
    required int    tcpPort,
    required String sid,
    required int    gen,
  }) async {
    final generation = _lifecycleGeneration;
    final client = LanLobbyClient();
    try {
      await client.connect(
        hostIp:   hostIp,
        hostPort: tcpPort,
        sid:      sid,
        gen:      gen,
        localFp:  _localFp,
        name:     _name,
        suffix:   _suffix,
      );

      if (_disposed || generation != _lifecycleGeneration || _role != _LobbyRole.joining) {
        await client.close().catchError((_) {});
        return;
      }

      _client              = client;
      _clientFrameSub      = client.frames.listen(_onHostFrame, cancelOnError: false);
      _clientDisconnectSub = client.disconnected.listen((_) => _onHostDisconnect(), cancelOnError: false);
    } catch (_) {
      await client.close().catchError((_) {});
      // Connection failed — try election from scratch if still in this lifecycle.
      if (_disposed || generation != _lifecycleGeneration) return;
      _role = _LobbyRole.discovering;
      await _runElection(survivors: [_localFp]);
    }
  }

  void _onHostFrame(Map<String, dynamic> frame) {
    try {
      _onHostFrameUnsafe(frame);
    } catch (_) {}
  }

  void _onHostFrameUnsafe(Map<String, dynamic> frame) {
    final type = frame['t'] as String?;
    if (type == kFtJoined) {
      if (_role != _LobbyRole.joining) return;
      _handleJoined(frame);
      return;
    }

    final state = _state;
    if (state == null || _role != _LobbyRole.joined) return;

    if (frame['sid'] != state.sessionId ||
        frame['gen'] != state.generation) {
      return;
    }

    switch (type) {
      case kFtMemberUpdate:
        _handleMemberUpdate(frame);
      case kFtMsg:
        _deliverMessage(frame);
      case kFtPing:
        _client?.send({
          'v': kLobbyProtocolVersion, 't': kFtPong,
          'sid': state.sessionId, 'gen': state.generation,
        });
      case kFtHostXferCommit:
        _handleHostXferCommit(frame);
      case kFtHostXferPrepare:
        _handleHostXferPrepare(frame);
    }
  }

  void _handleJoined(Map<String, dynamic> frame) {
    final sid     = frame['sid']     as String? ?? '';
    final gen     = (frame['gen']    as num?)?.toInt() ?? 0;
    final hostFp  = frame['hostFp']  as String? ?? '';
    final mv      = (frame['mv']     as num?)?.toInt() ?? 0;
    final members = membersFromJson(frame['members']);

    // Ensure we are in the member list
    final hasSelf = members.any((m) => m.fp == _localFp);
    final allMembers = hasSelf
        ? members
        : [...members, LobbyMember(fp: _localFp, name: _name, suffix: _suffix)];

    _state = LobbyState(
      sessionId:         sid,
      members:           allMembers,
      localFp:           _localFp,
      hostFp:            hostFp,
      generation:        gen,
      membershipVersion: mv,
    );
    _role = _LobbyRole.joined;
    _emitState();
  }

  void _handleMemberUpdate(Map<String, dynamic> frame) {
    final state = _state;
    if (state == null) return;
    final incomingGen = (frame['gen'] as num?)?.toInt() ?? -1;
    final incomingMv  = (frame['mv']  as num?)?.toInt() ?? -1;
    if (incomingGen != state.generation) return;
    if (incomingMv <= state.membershipVersion) return;

    final members = membersFromJson(frame['members']);
    _state = state.copyWith(
      membershipVersion: incomingMv,
      members:           members,
    );
    _emitState();
  }

  // ---------------------------------------------------------------------------
  // Host transfer — client side
  // ---------------------------------------------------------------------------

  void _handleHostXferPrepare(Map<String, dynamic> frame) {
    final nextHostFp = frame['nextHostFp'] as String?;
    if (nextHostFp != _localFp) return; // Not our turn
    final nextGen = (frame['nextGen'] as num?)?.toInt() ?? 0;
    final sid     = frame['sid']     as String? ?? (_state?.sessionId ?? '');

    // Close any previously opened pending server before starting a new one.
    _cancelPendingServer();

    final generation = _lifecycleGeneration;
    acceptHandoffPrepare(
      sid:        sid,
      nextGen:    nextGen,
      sendToHost: (f) => _client?.send(f),
    ).then((newServer) {
      if (newServer == null) return;
      if (_disposed ||
          generation != _lifecycleGeneration ||
          _role != _LobbyRole.joined) {
        newServer.close().catchError((_) {});
        return;
      }
      // We are now the pending host; start broadcasting so other clients can
      // start discovering us, but wait for COMMIT before taking the host role.
      _discovery.sendAnnounce(
        sid:         sid,
        gen:         nextGen,
        hostFp:      _localFp,
        tcpPort:     newServer.port,
        memberCount: _state?.memberCount ?? 1,
      );
      // Store the server so _handleHostXferCommit can adopt it.
      _pendingServer    = newServer;
      _pendingServerGen = nextGen;
      _pendingSid       = sid;
      // If COMMIT never arrives, clean up after a timeout.
      _pendingCommitTimer = Timer(kLobbyHandoffCommitTimeout, _cancelPendingServer);
    }).ignore();
  }

  LanLobbyServer? _pendingServer;
  int             _pendingServerGen = 0;
  String          _pendingSid       = '';
  Timer?          _pendingCommitTimer;

  void _cancelPendingServer() {
    _pendingCommitTimer?.cancel();
    _pendingCommitTimer = null;
    _pendingServer?.close().ignore();
    _pendingServer    = null;
    _pendingServerGen = 0;
    _pendingSid       = '';
  }

  void _handleHostXferCommit(Map<String, dynamic> frame) {
    final newHostFp  = frame['nextHostFp'] as String? ?? '';
    final commitSid  = frame['sid']        as String? ?? '';
    final commitGen  = (frame['nextGen'] as num?)?.toInt() ?? 0;
    if (newHostFp == _localFp &&
        _pendingServer != null &&
        commitSid == _pendingSid &&
        commitGen == _pendingServerGen) {
      // We won the handoff — transition to host role.
      _pendingCommitTimer?.cancel();
      _pendingCommitTimer = null;
      final server = _pendingServer!;
      final adoptSid = _pendingSid;
      final adoptGen = _pendingServerGen;
      _pendingServer    = null;
      _pendingServerGen = 0;
      _pendingSid       = '';
      _disconnectFromHost();
      _adoptServerRole(server, adoptSid, adoptGen);
    } else {
      // Another member became host — reconnect to them.
      final newPort = (frame['port'] as num?)?.toInt() ?? 0;
      if (newHostFp.isEmpty || newPort <= 0) return;

      // We need the new host's IP. It was in the announce we received earlier.
      // Re-discover via UDP since we don't have the IP stored.
      _disconnectFromHost();
      _role = _LobbyRole.discovering;
      // A fresh DISC_REQ will reach the new host quickly since they're already broadcasting.
      _discovery.sendDiscoveryRequest(_localFp);
      // The ANNOUNCE response will trigger _connectToHost via _handleAnnounce.
    }
  }

  void _adoptServerRole(LanLobbyServer server, String sid, int gen) {
    _server = server;
    _role   = _LobbyRole.hosting;

    // Rebuild with self as host; active list starts with just self.
    // Survivors re-JOIN within the recovery window and get added then.
    _state = LobbyState(
      sessionId:         sid,
      members:           [LobbyMember(fp: _localFp, name: _name, suffix: _suffix)],
      localFp:           _localFp,
      hostFp:            _localFp,
      generation:        gen,
      membershipVersion: 0,
    );
    _emitState();

    _serverJoinSub       = server.joinRequests.listen(_onClientJoin, cancelOnError: false);
    _serverFrameSub      = server.clientFrames.listen(_onClientFrame, cancelOnError: false);
    _serverDisconnectSub = server.disconnections.listen(_onClientDisconnect, cancelOnError: false);

    _startAnnouncing();
  }

  // ---------------------------------------------------------------------------
  // Host crash / unexpected disconnect (client side)
  // ---------------------------------------------------------------------------

  void _onHostDisconnect() {
    if (_role == _LobbyRole.leaving || _role == _LobbyRole.idle) return;
    _disconnectFromHost();
    _role = _LobbyRole.discovering;

    final survivors = _state?.members.map((m) => m.fp).toList() ?? [_localFp];
    final crashedFp = _state?.hostFp ?? '';
    final aliveFps  = survivors.where((fp) => fp != crashedFp).toList();

    _runElection(survivors: aliveFps.isEmpty ? [_localFp] : aliveFps).ignore();
  }

  Future<void> _runElection({required List<String> survivors}) async {
    if (_disposed) return;
    if (_electionRunning) return;
    _electionRunning = true;

    final generation = _lifecycleGeneration;
    try {
      final delay = electionDelay(_localFp, survivors);

      // Send one final discovery request
      _discovery.sendDiscoveryRequest(_localFp);

      // Wait computed delay while monitoring for an incoming ANNOUNCE
      await Future.delayed(delay);

      if (_disposed || generation != _lifecycleGeneration) return;
      if (_role != _LobbyRole.discovering) return; // Already resolved

      // No host found during the delay — self-elect
      final oldState = _state;
      final sid      = oldState?.sessionId ?? _uuid.v4();
      final gen      = (oldState?.generation ?? -1) + 1;
      await _becomeHost(sid: sid, gen: gen);
    } finally {
      _electionRunning = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Surrender host role (conflict resolution)
  // ---------------------------------------------------------------------------

  void _surrenderHostTo(String winnerIp, int winnerPort, Map<String, dynamic> frame) {
    _stopAnnouncing();
    final server = _server;
    _server = null;

    // Notify our connected clients to find the new host
    final state   = _state;
    final sid     = frame['sid']     as String? ?? (state?.sessionId ?? '');
    final gen     = (frame['gen']    as num?)?.toInt() ?? 0;
    final hostFp  = frame['hostFp']  as String? ?? '';
    final tcpPort = (frame['port']   as num?)?.toInt() ?? 0;

    server?.broadcastFrame({
      'v':          kLobbyProtocolVersion,
      't':          kFtHostXferCommit,
      'sid':        sid,
      'nextHostFp': hostFp,
      'port':       tcpPort,
      'nextGen':    gen,
    });
    server?.close().ignore();

    _clearServerSubs();
    _role = _LobbyRole.discovering;
    _connectToHost(winnerIp, tcpPort, frame);
  }

  // ---------------------------------------------------------------------------
  // Leave
  // ---------------------------------------------------------------------------

  Future<void> _doLeave() async {
    _role = _LobbyRole.leaving;
    _lifecycleGeneration++;

    final announceTimer = _announceTimer;
    _announceTimer = null;

    final discoverySub = _discoverySub;
    _discoverySub = null;

    final server = _server;
    _server = null;

    final serverJoinSub = _serverJoinSub;
    _serverJoinSub = null;
    final serverFrameSub = _serverFrameSub;
    _serverFrameSub = null;
    final serverDisconnectSub = _serverDisconnectSub;
    _serverDisconnectSub = null;

    final clientFrameSub = _clientFrameSub;
    _clientFrameSub = null;
    final clientDisconnectSub = _clientDisconnectSub;
    _clientDisconnectSub = null;
    final client = _client;
    _client = null;

    final pendingServer = _pendingServer;
    _pendingServer = null;
    final pendingCommitTimer = _pendingCommitTimer;
    _pendingCommitTimer = null;

    try {
      announceTimer?.cancel();
      pendingCommitTimer?.cancel();

      if (discoverySub != null) {
        await discoverySub.cancel().catchError((_) {});
      }
      if (serverJoinSub != null) {
        await serverJoinSub.cancel().catchError((_) {});
      }
      if (serverFrameSub != null) {
        await serverFrameSub.cancel().catchError((_) {});
      }
      if (serverDisconnectSub != null) {
        await serverDisconnectSub.cancel().catchError((_) {});
      }
      if (clientFrameSub != null) {
        await clientFrameSub.cancel().catchError((_) {});
      }
      if (clientDisconnectSub != null) {
        await clientDisconnectSub.cancel().catchError((_) {});
      }

      if (server != null && server.isOpen) {
        final state      = _state;
        final memberFps  = state?.members.map((m) => m.fp).toList() ?? [];
        final sid        = state?.sessionId ?? '';
        final currentGen = state?.generation ?? 0;

        try {
          final result = await runGracefulHandoff(
            server:     server,
            sid:        sid,
            currentGen: currentGen,
            localFp:    _localFp,
            memberFps:  memberFps,
          );
          if (result != null) {
            await Future.delayed(const Duration(milliseconds: 200));
          }
        } catch (_) {}
        await server.close().catchError((_) {});
      }

      if (client != null) {
        await client.close().catchError((_) {});
      }

      if (pendingServer != null) {
        await pendingServer.close().catchError((_) {});
      }
    } finally {
      try {
        _discovery.close();
      } catch (_) {}
      try {
        await _lock.release();
      } catch (_) {}

      _state = null;
      _role  = _LobbyRole.idle;
      _emitState();
    }
  }

  void _disconnectFromHost() {
    _clientFrameSub?.cancel();
    _clientFrameSub = null;
    _clientDisconnectSub?.cancel();
    _clientDisconnectSub = null;
    _client?.close().ignore();
    _client = null;
  }

  void _clearServerSubs() {
    _serverJoinSub?.cancel();
    _serverJoinSub = null;
    _serverFrameSub?.cancel();
    _serverFrameSub = null;
    _serverDisconnectSub?.cancel();
    _serverDisconnectSub = null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _deliverMessage(Map<String, dynamic> frame) {
    final msgId = frame['msgId'] as String?;
    if (msgId == null) return;
    if (_seenMsgIds.contains(msgId)) return;
    _seenMsgIds.add(msgId);
    if (_seenMsgIds.length > kLobbyMsgIdCacheSize) _seenMsgIds.removeAt(0);

    final senderFp   = frame['fp']   as String? ?? '';
    final senderName = frame['name'] as String? ?? senderFp.substring(0, senderFp.length.clamp(0, 8));
    final text       = frame['text'] as String? ?? '';
    final ts         = (frame['ts']  as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;

    if (text.isEmpty) return;
    if (!_messageCtrl.isClosed) {
      _messageCtrl.add(LobbyMessage(
        msgId:      msgId,
        senderFp:   senderFp,
        senderName: senderName,
        text:       text,
        sentAt:     DateTime.fromMillisecondsSinceEpoch(ts),
      ));
    }
  }

  void _emitState() {
    if (!_stateCtrl.isClosed) _stateCtrl.add(_state);
  }
}
