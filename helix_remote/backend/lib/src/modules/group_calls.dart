import 'dart:convert';
import 'dart:math';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/websocket.dart';

/// HTTP module for F8 group calls, call links, and scheduled calls.
///
/// POST /                           — create room
/// GET  /:roomId                    — get room state + participants
/// POST /:roomId/join               — join room
/// POST /:roomId/leave              — leave room
/// POST /:roomId/end                — host ends room
/// POST /:roomId/kick               — host kicks participant
/// POST /:roomId/key                — deliver wrapped room key (host only)
/// POST /:roomId/screen-sharing     — toggle screen-share flag
/// POST /links                      — create call link
/// GET  /links/:token               — resolve call link
/// DELETE /links/:token             — revoke call link
/// POST /scheduled                  — create scheduled call
/// GET  /scheduled                  — list upcoming scheduled calls
/// POST /scheduled/:id/rsvp         — RSVP to scheduled call
/// DELETE /scheduled/:id            — cancel scheduled call (host)
class GroupCallsModule {
  GroupCallsModule(this.db, this.wsRelay);

  final BackendDatabase db;
  final WebSocketRelay wsRelay;

  static const int _maxParticipants = 4;
  static const int _linkExpiryMs = 7 * 24 * 60 * 60 * 1000;
  static const int _maxTitleLength = 200;
  static const int _maxWrappedKeyLength = 2048;

  Router get router {
    final r = Router();
    r.post('/', _handleCreateRoom);
    r.get('/<roomId>', _handleGetRoom);
    r.post('/<roomId>/join', _handleJoinRoom);
    r.post('/<roomId>/leave', _handleLeaveRoom);
    r.post('/<roomId>/end', _handleEndRoom);
    r.post('/<roomId>/kick', _handleKickParticipant);
    r.post('/<roomId>/key', _handleDeliverRoomKey);
    r.post('/<roomId>/screen-sharing', _handleScreenSharing);
    r.post('/links', _handleCreateLink);
    r.get('/links/<token>', _handleResolveLink);
    r.delete('/links/<token>', _handleRevokeLink);
    r.post('/scheduled', _handleCreateScheduled);
    r.get('/scheduled', _handleListScheduled);
    r.post('/scheduled/<id>/rsvp', _handleRsvp);
    r.delete('/scheduled/<id>', _handleCancelScheduled);
    return r;
  }

  // ---------------------------------------------------------------------------
  // Room management
  // ---------------------------------------------------------------------------

  Future<Response> _handleCreateRoom(Request request) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final body = await _readJson(request);
    if (body == null) return _badRequest('Invalid JSON');
    final isVideo = body['is_video'] == true;
    final scheduledCallId = body['scheduled_call_id'] as String?;
    final now = DateTime.now().millisecondsSinceEpoch;
    final roomId = _newId('room');
    db.createCallRoom(
      roomId: roomId,
      hostAccountId: auth['account_id'] as String,
      hostDeviceId: auth['device_id'] as String,
      isVideo: isVideo,
      now: now,
    );
    if (scheduledCallId != null) {
      final sc = db.getScheduledCall(scheduledCallId);
      if (sc != null &&
          sc['host_account_id'] == auth['account_id'] &&
          sc['cancelled_at'] == null) {
        db.linkRoomToScheduledCall(
          scheduledCallId: scheduledCallId,
          roomId: roomId,
        );
      }
    }
    return _ok({'status': 'created', 'room_id': roomId, 'is_video': isVideo});
  }

  Future<Response> _handleGetRoom(Request request, String roomId) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final room = db.getCallRoom(roomId);
    if (room == null) return _notFound('room not found');
    final participants = db.getCallRoomParticipants(roomId);
    return _ok({...room, 'participants': participants});
  }

  Future<Response> _handleJoinRoom(Request request, String roomId) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final room = db.getCallRoom(roomId);
    if (room == null) return _notFound('room not found');
    if (room['status'] == 'ENDED') {
      return _json(410, {'error': 'room has ended'});
    }
    final active = db.countActiveParticipants(roomId);
    if (active >= _maxParticipants) {
      return _json(409, {'error': 'room_full', 'max': _maxParticipants});
    }
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    db.joinCallRoom(
      roomId: roomId,
      accountId: accountId,
      deviceId: deviceId,
      now: now,
    );
    _broadcastRoomEvent(
      roomId: roomId,
      type: 'participant_joined',
      payload: {
        'account_id': accountId,
        'device_id': deviceId,
        'is_video': room['is_video'],
      },
      excludeDevice: deviceId,
    );
    return _ok({'status': 'joined', 'room_id': roomId});
  }

  Future<Response> _handleLeaveRoom(Request request, String roomId) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final deviceId = auth['device_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    db.leaveCallRoom(roomId: roomId, deviceId: deviceId, now: now);
    _broadcastRoomEvent(
      roomId: roomId,
      type: 'participant_left',
      payload: {'account_id': auth['account_id'], 'device_id': deviceId},
      excludeDevice: deviceId,
    );
    return _ok({'status': 'left', 'room_id': roomId});
  }

  Future<Response> _handleEndRoom(Request request, String roomId) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final room = db.getCallRoom(roomId);
    if (room == null) return _notFound('room not found');
    if (room['host_account_id'] != auth['account_id']) {
      return _json(403, {'error': 'only the host can end the room'});
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.endCallRoom(roomId, now);
    _broadcastRoomEvent(
      roomId: roomId,
      type: 'room_ended',
      payload: {'room_id': roomId},
    );
    return _ok({'status': 'ended', 'room_id': roomId});
  }

  Future<Response> _handleKickParticipant(
    Request request,
    String roomId,
  ) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final room = db.getCallRoom(roomId);
    if (room == null) return _notFound('room not found');
    if (room['host_account_id'] != auth['account_id']) {
      return _json(403, {'error': 'only the host can kick participants'});
    }
    final body = await _readJson(request);
    if (body == null) return _badRequest('Invalid JSON');
    final targetDeviceId = body['device_id'] as String?;
    if (targetDeviceId == null || targetDeviceId.isEmpty) {
      return _badRequest('device_id is required');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.kickFromRoom(roomId: roomId, deviceId: targetDeviceId, now: now);
    _broadcastRoomEvent(
      roomId: roomId,
      type: 'participant_kicked',
      payload: {'device_id': targetDeviceId},
    );
    return _ok({'status': 'kicked', 'device_id': targetDeviceId});
  }

  Future<Response> _handleDeliverRoomKey(Request request, String roomId) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final room = db.getCallRoom(roomId);
    if (room == null) return _notFound('room not found');
    if (room['host_account_id'] != auth['account_id']) {
      return _json(403, {'error': 'only the host can deliver room keys'});
    }
    final body = await _readJson(request);
    if (body == null) return _badRequest('Invalid JSON');
    final keyId = body['key_id'] as String?;
    final epoch = body['epoch'] as int?;
    final keys = body['keys'] as List<dynamic>?;
    if (keyId == null || keyId.isEmpty) return _badRequest('key_id required');
    if (epoch == null || epoch < 0) return _badRequest('epoch required');
    if (keys == null || keys.isEmpty) return _badRequest('keys required');
    db.upsertRoomKeyId(roomId: roomId, keyId: keyId, epoch: epoch);
    var saved = 0;
    for (final entry in keys) {
      if (entry is! Map<String, dynamic>) continue;
      final did = entry['device_id'] as String?;
      final wk = entry['wrapped_key'] as String?;
      if (did == null || wk == null || wk.length > _maxWrappedKeyLength) {
        continue;
      }
      db.saveWrappedRoomKey(
        roomId: roomId,
        epoch: epoch,
        deviceId: did,
        wrappedKey: wk,
      );
      saved++;
    }
    return _ok({
      'status': 'delivered',
      'key_id': keyId,
      'epoch': epoch,
      'saved': saved,
    });
  }

  Future<Response> _handleScreenSharing(Request request, String roomId) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final body = await _readJson(request);
    if (body == null) return _badRequest('Invalid JSON');
    final active = body['active'] == true;
    final deviceId = auth['device_id'] as String;
    db.setScreenSharing(roomId: roomId, deviceId: deviceId, active: active);
    _broadcastRoomEvent(
      roomId: roomId,
      type: 'screen_sharing_changed',
      payload: {'device_id': deviceId, 'active': active},
      excludeDevice: deviceId,
    );
    return _ok({'status': 'updated', 'active': active});
  }

  // ---------------------------------------------------------------------------
  // Call links
  // ---------------------------------------------------------------------------

  Future<Response> _handleCreateLink(Request request) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final body = await _readJson(request);
    if (body == null) return _badRequest('Invalid JSON');
    final requiresApproval = body['requires_approval'] == true;
    final maxUses = (body['max_uses'] as int?) ?? 0;
    final roomId = body['room_id'] as String?;
    final accountId = auth['account_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    final linkId = _newId('lnk');
    final linkToken = _newLinkToken();
    db.createCallLink(
      linkId: linkId,
      linkToken: linkToken,
      roomId: roomId,
      createdBy: accountId,
      requiresApproval: requiresApproval,
      maxUses: maxUses,
      createdAt: now,
      expiresAt: now + _linkExpiryMs,
    );
    return _ok({
      'status': 'created',
      'link_id': linkId,
      'link_token': linkToken,
      'requires_approval': requiresApproval,
    });
  }

  Future<Response> _handleResolveLink(Request request, String token) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final link = db.getCallLinkByToken(token);
    if (link == null) return _notFound('call link not found');
    if (link['revoked_at'] != null) {
      return _json(410, {'error': 'call link has been revoked'});
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((link['expires_at'] as int) <= now) {
      return _json(410, {'error': 'call link has expired'});
    }
    final maxUses = link['max_uses'] as int;
    if (maxUses > 0 && (link['use_count'] as int) >= maxUses) {
      return _json(409, {'error': 'call link use limit reached'});
    }
    final roomId = link['room_id'] as String?;
    Map<String, dynamic>? roomInfo;
    if (roomId != null) {
      final room = db.getCallRoom(roomId);
      if (room != null && room['status'] != 'ENDED') {
        roomInfo = {
          'room_id': room['room_id'],
          'status': room['status'],
          'is_video': room['is_video'],
          'participant_count': db.countActiveParticipants(roomId),
        };
      }
    }
    return _ok({
      'link_id': link['link_id'],
      'requires_approval': link['requires_approval'],
      'room': roomInfo,
    });
  }

  Future<Response> _handleRevokeLink(Request request, String token) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final link = db.getCallLinkByToken(token);
    if (link == null) return _notFound('call link not found');
    if (link['created_by'] != auth['account_id']) {
      return _json(403, {'error': 'only the link creator can revoke it'});
    }
    final linkId = link['link_id'];
    if (linkId is! String) return _badRequest('invalid link');
    db.revokeCallLink(linkId, DateTime.now().millisecondsSinceEpoch);
    return _ok({'status': 'revoked', 'link_token': token});
  }

  // ---------------------------------------------------------------------------
  // Scheduled calls
  // ---------------------------------------------------------------------------

  Future<Response> _handleCreateScheduled(Request request) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final body = await _readJson(request);
    if (body == null) return _badRequest('Invalid JSON');
    final title = (body['title'] as String?) ?? '';
    if (title.isEmpty || title.length > _maxTitleLength) {
      return _badRequest('title required (max $_maxTitleLength chars)');
    }
    final scheduledAt = body['scheduled_at'] as int?;
    if (scheduledAt == null ||
        scheduledAt <= DateTime.now().millisecondsSinceEpoch) {
      return _badRequest('scheduled_at must be a future timestamp (ms)');
    }
    final rawAttendees = (body['attendee_ids'] as List<dynamic>?) ?? [];
    final attendeeIds = rawAttendees.whereType<String>().toList();
    final accountId = auth['account_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;
    final scId = _newId('sc');
    db.createScheduledCall(
      scheduledCallId: scId,
      hostAccountId: accountId,
      title: title,
      scheduledAt: scheduledAt,
      createdAt: now,
      attendeeIds: attendeeIds,
    );
    // Notify attendees via WebSocket (best-effort per device).
    for (final aid in attendeeIds) {
      final envelope = {
        'event_id': _newId('scev'),
        'schema_version': 1,
        'timestamp': now,
        'type': 'scheduled_call_invite',
        'payload': {
          'scheduled_call_id': scId,
          'title': title,
          'host_account_id': accountId,
          'scheduled_at': scheduledAt,
        },
      };
      for (final dev in db.getDevices(aid)) {
        wsRelay.trySendToDevice(dev['device_id'] as String, envelope);
      }
    }
    return _ok({
      'status': 'created',
      'scheduled_call_id': scId,
      'title': title,
    });
  }

  Future<Response> _handleListScheduled(Request request) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final afterMs = DateTime.now().millisecondsSinceEpoch;
    final calls = db.getScheduledCallsForAccount(
      auth['account_id'] as String,
      afterMs,
    );
    return _ok({'calls': calls});
  }

  Future<Response> _handleRsvp(Request request, String id) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final body = await _readJson(request);
    if (body == null) return _badRequest('Invalid JSON');
    final sc = db.getScheduledCall(id);
    if (sc == null) return _notFound('scheduled call not found');
    if (sc['cancelled_at'] != null) {
      return _json(410, {'error': 'scheduled call was cancelled'});
    }
    final rsvp = body['rsvp'] as String?;
    if (rsvp != 'YES' && rsvp != 'NO') {
      return _badRequest('rsvp must be YES or NO');
    }
    db.rsvpScheduledCall(
      scheduledCallId: id,
      accountId: auth['account_id'] as String,
      rsvpStatus: rsvp!,
    );
    return _ok({'status': 'rsvp_recorded', 'rsvp': rsvp});
  }

  Future<Response> _handleCancelScheduled(Request request, String id) async {
    final auth = _auth(request);
    if (auth == null) return _unauthorized();
    final sc = db.getScheduledCall(id);
    if (sc == null) return _notFound('scheduled call not found');
    if (sc['host_account_id'] != auth['account_id']) {
      return _json(403, {'error': 'only the host can cancel'});
    }
    if (sc['cancelled_at'] != null) {
      return _json(409, {'error': 'already cancelled'});
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    db.cancelScheduledCall(id, now);
    // Notify attendees via WebSocket (best-effort per device).
    final attendees = db.getScheduledCallAttendees(id);
    for (final a in attendees) {
      final envelope = {
        'event_id': _newId('scev'),
        'schema_version': 1,
        'timestamp': now,
        'type': 'scheduled_call_cancelled',
        'payload': {'scheduled_call_id': id, 'title': sc['title']},
      };
      for (final dev in db.getDevices(a['account_id'] as String)) {
        wsRelay.trySendToDevice(dev['device_id'] as String, envelope);
      }
    }
    return _ok({'status': 'cancelled', 'scheduled_call_id': id});
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _broadcastRoomEvent({
    required String roomId,
    required String type,
    required Map<String, dynamic> payload,
    String? excludeDevice,
  }) {
    final participants = db.getCallRoomParticipants(roomId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final envelope = {
      'event_id': _newId('gcevt'),
      'schema_version': 1,
      'timestamp': now,
      'type': type,
      'payload': {'room_id': roomId, ...payload},
    };
    for (final p in participants) {
      final did = p['device_id'] as String;
      if (did == excludeDevice) continue;
      if (p['status'] != 'JOINED') continue;
      wsRelay.trySendToDevice(did, envelope);
    }
  }

  Map<String, dynamic>? _auth(Request request) =>
      request.context['auth'] as Map<String, dynamic>?;

  Response _unauthorized() => _json(401, {'error': 'Unauthorized'});
  Response _badRequest(String msg) => _json(400, {'error': msg});
  Response _notFound(String msg) => _json(404, {'error': msg});
  Response _ok(Map<String, dynamic> body) => _json(200, body);

  Response _json(int status, Map<String, dynamic> body) {
    final encoded = jsonEncode(body);
    if (status == 200) {
      return Response.ok(
        encoded,
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response(
      status,
      body: encoded,
      headers: {'Content-Type': 'application/json'},
    );
  }

  Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final raw = await request.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static final _rng = Random.secure();

  String _newId(String prefix) {
    final bytes = List<int>.generate(12, (_) => _rng.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${prefix}_$hex';
  }

  String _newLinkToken() {
    // 32 random bytes → 64-char hex token (high entropy, URL-safe).
    final bytes = List<int>.generate(32, (_) => _rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
