import 'package:flutter_test/flutter_test.dart';
import 'package:helix_domain/application/state_machines/workflow_states.dart';
import 'package:helix_domain/application/state_machines/workflow_transitions.dart';

void main() {
  test('peer connection state machine accepts expected happy path', () {
    var state = PeerConnectionPhase.disconnected;
    state = transitionPeerConnection(state, PeerConnectionPhase.discovering);
    state = transitionPeerConnection(state, PeerConnectionPhase.connecting);
    state = transitionPeerConnection(
      state,
      PeerConnectionPhase.securingChannel,
    );
    state = transitionPeerConnection(state, PeerConnectionPhase.authenticating);
    state = transitionPeerConnection(
      state,
      PeerConnectionPhase.negotiatingCapabilities,
    );
    state = transitionPeerConnection(state, PeerConnectionPhase.connected);

    expect(state, PeerConnectionPhase.connected);
  });

  test('file transfer state machine rejects impossible transition', () {
    expect(
      () => transitionFileTransfer(
        FileTransferPhase.completed,
        FileTransferPhase.transferring,
      ),
      throwsA(isA<WorkflowTransitionError>()),
    );
  });

  test('group election state machine cycles back to stable', () {
    var state = GroupElectionPhase.stable;
    state = transitionGroupElection(
      state,
      GroupElectionPhase.electionTriggered,
    );
    state = transitionGroupElection(state, GroupElectionPhase.voting);
    state = transitionGroupElection(state, GroupElectionPhase.hostElected);
    state = transitionGroupElection(state, GroupElectionPhase.syncing);
    state = transitionGroupElection(state, GroupElectionPhase.stable);

    expect(state, GroupElectionPhase.stable);
  });
}
