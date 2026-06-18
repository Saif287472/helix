import 'package:helix_domain/application/state_machines/workflow_states.dart';

class WorkflowTransitionError implements Exception {
  const WorkflowTransitionError(this.message);

  final String message;

  @override
  String toString() => 'WorkflowTransitionError: $message';
}

T requireAllowedTransition<T extends Enum>(
  T from,
  T to,
  Map<T, Set<T>> transitions,
) {
  if (from == to || (transitions[from]?.contains(to) ?? false)) {
    return to;
  }
  throw WorkflowTransitionError('Invalid transition: $from -> $to');
}

PeerConnectionPhase transitionPeerConnection(
  PeerConnectionPhase from,
  PeerConnectionPhase to,
) {
  return requireAllowedTransition(from, to, _peerConnectionTransitions);
}

FileTransferPhase transitionFileTransfer(
  FileTransferPhase from,
  FileTransferPhase to,
) {
  return requireAllowedTransition(from, to, _fileTransferTransitions);
}

GroupElectionPhase transitionGroupElection(
  GroupElectionPhase from,
  GroupElectionPhase to,
) {
  return requireAllowedTransition(from, to, _groupElectionTransitions);
}

const Map<PeerConnectionPhase, Set<PeerConnectionPhase>>
_peerConnectionTransitions = {
  PeerConnectionPhase.disconnected: {
    PeerConnectionPhase.discovering,
    PeerConnectionPhase.connecting,
  },
  PeerConnectionPhase.discovering: {
    PeerConnectionPhase.connecting,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.connecting: {
    PeerConnectionPhase.awaitingApproval,
    PeerConnectionPhase.securingChannel,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.awaitingApproval: {
    PeerConnectionPhase.securingChannel,
    PeerConnectionPhase.closing,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.securingChannel: {
    PeerConnectionPhase.authenticating,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.authenticating: {
    PeerConnectionPhase.negotiatingCapabilities,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.negotiatingCapabilities: {
    PeerConnectionPhase.connected,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.connected: {
    PeerConnectionPhase.reconnecting,
    PeerConnectionPhase.closing,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.reconnecting: {
    PeerConnectionPhase.connected,
    PeerConnectionPhase.failed,
  },
  PeerConnectionPhase.closing: {PeerConnectionPhase.disconnected},
  PeerConnectionPhase.failed: {
    PeerConnectionPhase.disconnected,
    PeerConnectionPhase.reconnecting,
  },
};

const Map<FileTransferPhase, Set<FileTransferPhase>> _fileTransferTransitions =
    {
      FileTransferPhase.proposed: {
        FileTransferPhase.awaitingAcceptance,
        FileTransferPhase.preparing,
        FileTransferPhase.cancelled,
      },
      FileTransferPhase.awaitingAcceptance: {
        FileTransferPhase.preparing,
        FileTransferPhase.cancelled,
        FileTransferPhase.failed,
      },
      FileTransferPhase.preparing: {
        FileTransferPhase.transferring,
        FileTransferPhase.failed,
      },
      FileTransferPhase.transferring: {
        FileTransferPhase.paused,
        FileTransferPhase.verifying,
        FileTransferPhase.cancelled,
        FileTransferPhase.failed,
      },
      FileTransferPhase.paused: {
        FileTransferPhase.transferring,
        FileTransferPhase.cancelled,
        FileTransferPhase.failed,
      },
      FileTransferPhase.verifying: {
        FileTransferPhase.completed,
        FileTransferPhase.failed,
      },
      FileTransferPhase.completed: {},
      FileTransferPhase.cancelled: {},
      FileTransferPhase.failed: {
        FileTransferPhase.preparing,
        FileTransferPhase.cancelled,
      },
    };

const Map<GroupElectionPhase, Set<GroupElectionPhase>>
_groupElectionTransitions = {
  GroupElectionPhase.stable: {GroupElectionPhase.electionTriggered},
  GroupElectionPhase.electionTriggered: {GroupElectionPhase.voting},
  GroupElectionPhase.voting: {GroupElectionPhase.hostElected},
  GroupElectionPhase.hostElected: {GroupElectionPhase.syncing},
  GroupElectionPhase.syncing: {GroupElectionPhase.stable},
};
