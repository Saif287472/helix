import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/groups/application/group_errors.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

/// Every refusal a group operation can meet is said in plain words and never
/// as an exception: a stale roster, a missing permission, a privacy setting,
/// a link that is gone.
void main() {
  ApiException api(ErrorCode code) =>
      ApiException(status: code.status, code: code);

  test('engine refusals', () {
    expect(
      groupErrorText(const GroupException(GroupFailure.notAllowed)),
      'Only an admin can do that in this group.',
    );
    expect(
      groupErrorText(
        const GroupException(GroupFailure.notAllowed),
        context: GroupContext.members,
      ),
      'This group only lets admins do that.',
    );
    expect(
      groupErrorText(const GroupException(GroupFailure.notAMember)),
      'You are not in this group any more.',
    );
    expect(
      groupErrorText(const GroupException(GroupFailure.noGroupKey)),
      contains('still being set up'),
    );
    expect(
      groupErrorText(const GroupException(GroupFailure.versionConflict)),
      contains('changed at the same time'),
    );
    expect(
      groupErrorText(const GroupException(GroupFailure.badLink)),
      contains('not a Helix group link'),
    );
  });

  test('server answers are said by context', () {
    expect(
      groupErrorText(api(ErrorCode.forbidden)),
      'You do not have permission to do that in this group.',
    );
    expect(
      groupErrorText(api(ErrorCode.forbidden), context: GroupContext.link),
      'You cannot join this group.',
    );
    expect(
      groupErrorText(api(ErrorCode.notFound), context: GroupContext.link),
      contains('no longer valid'),
    );
    expect(
      groupErrorText(api(ErrorCode.notFound)),
      contains('may have been deleted'),
    );
    expect(groupErrorText(api(ErrorCode.expired)), contains('has expired'));
    expect(groupErrorText(api(ErrorCode.groupFull)), contains('1,024'));
    expect(
      groupErrorText(api(ErrorCode.deviceListStale)),
      contains('member list changed'),
    );
    expect(
      groupErrorText(api(ErrorCode.rateLimited)),
      contains('Too many attempts'),
    );
    expect(
      groupErrorText(api(ErrorCode.federationUnavailable)),
      contains('server could not be reached'),
    );
    expect(groupErrorText(api(ErrorCode.internal)), contains('busy'));
  });

  test('network and sign-out', () {
    expect(groupErrorText(const NetworkException()), contains('No connection'));
    expect(
      groupErrorText(const SignedOutException(SignedOutReason.noSession)),
      contains('signed out'),
    );
  });

  test('anything else is generic and leaks nothing', () {
    final text = groupErrorText(StateError('secret link HLX-GRP-abc'));
    expect(text, 'Something went wrong. Try again.');
    expect(text, isNot(contains('HLX-GRP')));
    expect(
      groupErrorText(ArgumentError('x')),
      'Enter a group name of 1 to 100 characters.',
    );
  });

  test('a privacy refusal names the person and offers a link', () {
    expect(
      addRejectionText(AddRejection.privacy, 'Ada'),
      'Ada only lets people they know add them to groups. Send them an '
      'invite link instead.',
    );
    expect(addRejectionText(AddRejection.banned, 'Ada'), contains('banned'));
    expect(
      addRejectionText(AddRejection.alreadyMember, 'Ada'),
      'Ada is already in this group.',
    );
    expect(
      addRejectionText(AddRejection.notFound, 'Ada'),
      'Ada could not be found.',
    );
  });

  test('losing the group is said for each reason', () {
    expect(membershipEndedText('left'), 'You left this group.');
    expect(membershipEndedText('deleted'), 'This group was deleted.');
    expect(membershipEndedText('removed'), 'You were removed from this group.');
  });
}
