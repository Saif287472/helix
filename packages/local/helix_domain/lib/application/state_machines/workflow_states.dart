enum PeerConnectionPhase {
  disconnected,
  discovering,
  connecting,
  awaitingApproval,
  securingChannel,
  authenticating,
  negotiatingCapabilities,
  connected,
  reconnecting,
  closing,
  failed,
}

enum FileTransferPhase {
  proposed,
  awaitingAcceptance,
  preparing,
  transferring,
  paused,
  verifying,
  completed,
  cancelled,
  failed,
}

enum CallSessionPhase {
  idle,
  offering,
  ringing,
  connecting,
  active,
  onHold,
  ending,
  ended,
  failed,
}

enum GroupElectionPhase {
  stable,
  electionTriggered,
  voting,
  hostElected,
  syncing,
}

enum ApplicationLifecyclePhase {
  initializing,
  ready,
  backgrounded,
  foregrounded,
  shuttingDown,
}

enum ReconnectionPhase {
  connected,
  disconnected,
  waitingToRetry,
  reconnecting,
  failed,
}
