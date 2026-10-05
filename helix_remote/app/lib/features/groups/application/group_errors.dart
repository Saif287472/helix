import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote_api/v2.dart'
    show ApiException, NetworkException, SignedOutException;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show GroupException, GroupFailure;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;
import 'package:helix_remote/features/groups/application/group_models.dart';

/// What a group operation was doing, so the same server answer can be said the
/// way that helps (`not_found` on a link means the link, on a group means the
/// group).
enum GroupContext { general, link, members, create }

/// The sentence for a failure of a group operation.
///
/// Plain English and never the exception's text: the server's wording is for
/// logs, and an exception can hold things (a link, an id) that must not reach
/// a screen. Stale rosters, missing permission and privacy refusals each get a
/// sentence that says what to do.
String groupErrorText(
  Object error, {
  GroupContext context = GroupContext.general,
}) {
  switch (error) {
    case GroupException(:final reason):
      return switch (reason) {
        GroupFailure.notAMember => 'You are not in this group any more.',
        GroupFailure.notAllowed =>
          context == GroupContext.members
              ? 'This group only lets admins do that.'
              : 'Only an admin can do that in this group.',
        GroupFailure.noGroupKey =>
          'This group is still being set up on your phone. Try again in a '
              'moment.',
        GroupFailure.versionConflict =>
          'The group was changed at the same time. Try again.',
        GroupFailure.badLink =>
          'That is not a Helix group link. Check that you copied all of it.',
        GroupFailure.badMention => 'That person is not in the group.',
      };
    case ApiException(:final code):
      return _apiText(code, context);
    case NetworkException() || SignedOutException():
      // Offline and signed out read the same on every screen.
      return describeFailure(error).message;
    case ArgumentError():
      return 'Enter a group name of 1 to 100 characters.';
  }
  return 'Something went wrong. Try again.';
}

String _apiText(ErrorCode code, GroupContext context) {
  final link = context == GroupContext.link;
  return switch (code) {
    ErrorCode.notAMember =>
      'You are not in this group any more, so you cannot change it.',
    ErrorCode.forbidden =>
      link
          ? 'You cannot join this group.'
          : 'You do not have permission to do that in this group.',
    ErrorCode.blocked =>
      'That is not possible: one of you has blocked the other.',
    ErrorCode.notFound =>
      link
          ? 'This invite link is no longer valid. Ask for a new one.'
          : context == GroupContext.members
          ? 'That person could not be found.'
          : 'This group could not be found. It may have been deleted.',
    ErrorCode.expired => 'This invite link has expired. Ask for a new one.',
    ErrorCode.conflict || ErrorCode.alreadyExists =>
      link
          ? 'You are already in this group, or already asked to join.'
          : 'That has already been done.',
    ErrorCode.groupFull => 'This group is full: it holds 1,024 people.',
    ErrorCode.versionConflict =>
      'The group was changed at the same time. Try again.',
    ErrorCode.deviceListStale =>
      'The member list changed while this was being sent. Try again.',
    ErrorCode.rateLimited => 'Too many attempts. Try again in a little while.',
    ErrorCode.invalidField ||
    ErrorCode.badRequest ||
    ErrorCode.payloadTooLarge =>
      'That could not be saved. Check what you entered and try again.',
    ErrorCode.federationUnavailable =>
      'The other person\'s server could not be reached. Try again later.',
    ErrorCode.accountSuspended ||
    ErrorCode.accountBanned => 'This account cannot do that right now.',
    ErrorCode.internal || ErrorCode.unavailable || ErrorCode.maintenance =>
      'The server is busy right now. Try again in a moment.',
    _ => 'Something went wrong. Try again.',
  };
}

/// Why [name] was not added, as one sentence.
String addRejectionText(AddRejection reason, String name) => switch (reason) {
  AddRejection.privacy =>
    '$name only lets people they know add them to groups. Send them an '
        'invite link instead.',
  AddRejection.banned => '$name is banned from this group. Unban them first.',
  AddRejection.notFound => '$name could not be found.',
  AddRejection.alreadyMember => '$name is already in this group.',
  AddRejection.unknown => '$name could not be added.',
};

/// What the screen says when this device is no longer in the group.
String membershipEndedText(String reason) => switch (reason) {
  'left' => 'You left this group.',
  'deleted' => 'This group was deleted.',
  _ => 'You were removed from this group.',
};
