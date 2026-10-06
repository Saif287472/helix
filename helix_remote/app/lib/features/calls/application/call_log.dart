import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/calls_port.dart';
import 'package:helix_remote/features/calls/application/start_call.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show CallLogRow, CallsDao;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One row of the Calls tab: consecutive calls with the same person, in the
/// same direction and on the same day, folded into one.
@immutable
final class CallLogEntry {
  const CallLogEntry({
    required this.item,
    required this.peer,
    required this.callIds,
  });

  /// What the tile draws; its `id` is the newest call's id.
  final HelixCallLogItem item;

  /// The other party's account id.
  final String peer;

  /// Every call folded into this row, newest first.
  final List<String> callIds;

  String get id => item.id;
  bool get video => item.video;

  @override
  bool operator ==(Object other) =>
      other is CallLogEntry &&
      other.item == item &&
      other.peer == peer &&
      listEquals(other.callIds, callIds);

  @override
  int get hashCode => Object.hash(item, peer, Object.hashAll(callIds));
}

/// The log's rows for the Calls tab, newest first.
///
/// Names come from the people-naming order, so a call from someone in the
/// phone book shows their phone-book name, then nickname, then number, then
/// `~Helix name`.
List<CallLogEntry> buildCallLog(
  List<CallLogRow> rows,
  PeopleDirectory names,
  DateTime now,
) {
  final entries = <_Folding>[];
  for (final row in rows) {
    final direction = _directionOf(row);
    final day = DateTime(
      row.startedAt.year,
      row.startedAt.month,
      row.startedAt.day,
    );
    final last = entries.isEmpty ? null : entries.last;
    if (last != null &&
        last.peer == row.peerAccountId &&
        last.direction == direction &&
        last.day == day) {
      last.callIds.add(row.callId);
      continue;
    }
    entries.add(_Folding(row, direction, day));
  }
  return [for (final folded in entries) folded.build(names, now)];
}

final class _Folding {
  _Folding(this.row, this.direction, this.day) : callIds = [row.callId];

  final CallLogRow row;
  final HelixCallDirection direction;
  final DateTime day;
  final List<String> callIds;

  String get peer => row.peerAccountId;

  CallLogEntry build(PeopleDirectory names, DateTime now) {
    final person = names.nameOf(peer, fallbackName: row.peerDisplayName);
    final title = person.display;
    final duration = CallsDao.durationSeconds(row);
    return CallLogEntry(
      peer: peer,
      callIds: List.unmodifiable(callIds),
      item: HelixCallLogItem(
        id: row.callId,
        title: title,
        avatar: HelixAvatarModel(
          name: title,
          colorIndex: HelixAvatarModel.colorIndexFor(peer),
        ),
        direction: direction,
        timeLabel: formatWhen(row.startedAt, now),
        video: row.video,
        count: callIds.length,
        isGroup: row.kind == 'group',
        durationLabel: duration == null || callIds.length > 1
            ? null
            : formatCallDuration(Duration(seconds: duration)),
      ),
    );
  }
}

/// The five directions the tile draws, from a log row.
HelixCallDirection _directionOf(CallLogRow row) {
  if (CallsDao.wasMissed(row)) return HelixCallDirection.missed;
  switch (row.state) {
    case 'failed':
      return HelixCallDirection.failed;
    case 'declined':
      return HelixCallDirection.declined;
    case 'missed':
      return row.direction == 'outgoing'
          ? HelixCallDirection.outgoing
          : HelixCallDirection.missed;
  }
  return row.direction == 'outgoing'
      ? HelixCallDirection.outgoing
      : HelixCallDirection.incoming;
}

/// The finer outcome of one call, for the detail page.
CallLogDirection detailDirectionOf(CallLogRow row) {
  if (CallsDao.wasMissed(row)) return CallLogDirection.missed;
  switch (row.state) {
    case 'failed':
      return CallLogDirection.failed;
    case 'declined':
      return CallLogDirection.declined;
    case 'cancelled':
      return row.direction == 'incoming'
          ? CallLogDirection.missed
          : CallLogDirection.cancelled;
    case 'unanswered':
      return row.direction == 'outgoing'
          ? CallLogDirection.noAnswer
          : CallLogDirection.missed;
  }
  return row.direction == 'outgoing'
      ? CallLogDirection.outgoing
      : CallLogDirection.incoming;
}

/// The Calls tab's rows, live.
final callLogProvider = StreamProvider<List<CallLogEntry>>((ref) async* {
  final names =
      ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
  final clock = ref.watch(clockProvider);
  final port = await ref.watch(callsPortProvider.future);
  yield* port
      .watchLog(limit: 200)
      .map((rows) => buildCallLog(rows, names, clock()));
});

/// [callLogProvider] narrowed to [query] (a name or number, case-insensitive);
/// the whole log for an empty query. This is the Calls tab's working local
/// search - the people search widget plugs in beside it.
final callLogSearchProvider =
    Provider.family<AsyncValue<List<CallLogEntry>>, String>((ref, query) {
      final log = ref.watch(callLogProvider);
      final needle = query.trim().toLowerCase();
      if (needle.isEmpty) return log;
      return log.whenData(
        (entries) => [
          for (final entry in entries)
            if (entry.item.title.toLowerCase().contains(needle)) entry,
        ],
      );
    });

/// One call in the detail page.
@immutable
final class CallDetailRow {
  const CallDetailRow({
    required this.callId,
    required this.direction,
    required this.timeLabel,
    required this.video,
    this.durationLabel,
    this.spokenDuration,
  });

  final String callId;
  final CallLogDirection direction;
  final String timeLabel;
  final bool video;
  final String? durationLabel;
  final String? spokenDuration;

  String get directionLabel => CallCopy.directionWord(direction);
}

/// Everything the call-detail page shows: the person and every call with them.
@immutable
final class CallDetail {
  const CallDetail({
    required this.peer,
    required this.title,
    required this.avatar,
    required this.rows,
    this.subtitle,
  });

  final String peer;
  final String title;
  final String? subtitle;
  final HelixAvatarModel avatar;

  /// Calls with this person, newest first; the one asked for first is the
  /// newest of its day (the page highlights nothing: the whole history helps).
  final List<CallDetailRow> rows;
}

/// The detail page's data for the call [callId] (its person and their calls),
/// or null when the call is no longer in the log.
final callDetailProvider = StreamProvider.family<CallDetail?, String>((
  ref,
  callId,
) async* {
  final names =
      ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
  final clock = ref.watch(clockProvider);
  final port = await ref.watch(callsPortProvider.future);
  yield* port.watchLog(limit: 200).map((rows) {
    final row = rows.where((r) => r.callId == callId).firstOrNull;
    if (row == null) return null;
    final peer = row.peerAccountId;
    final person = names.nameOf(peer, fallbackName: row.peerDisplayName);
    final now = clock();
    return CallDetail(
      peer: peer,
      title: person.display,
      subtitle: person.secondary,
      avatar: HelixAvatarModel(
        name: person.display,
        colorIndex: HelixAvatarModel.colorIndexFor(peer),
      ),
      rows: [
        for (final r in rows)
          if (r.peerAccountId == peer)
            CallDetailRow(
              callId: r.callId,
              direction: detailDirectionOf(r),
              timeLabel: formatWhen(r.startedAt, now),
              video: r.video,
              durationLabel: _durationOf(r),
              spokenDuration: _spokenOf(r),
            ),
      ],
    );
  });
});

String? _durationOf(CallLogRow row) {
  final seconds = CallsDao.durationSeconds(row);
  return seconds == null
      ? null
      : formatCallDuration(Duration(seconds: seconds));
}

String? _spokenOf(CallLogRow row) {
  final seconds = CallsDao.durationSeconds(row);
  return seconds == null
      ? null
      : spokenCallDuration(Duration(seconds: seconds));
}

/// What a person does on the call log.
final callLogActionsProvider = Provider<CallLogActions>(CallLogActions.new);

final class CallLogActions {
  CallLogActions(this._ref);

  final Ref _ref;

  /// Removes [callIds] from the log (a folded row holds several).
  Future<void> delete(Iterable<String> callIds) async {
    final port = await _ref.read(callsPortProvider.future);
    for (final id in callIds) {
      await port.forget(id);
    }
  }

  /// Calls [peer] back; the outcome carries the sentence to show when it did
  /// not start.
  Future<PlaceCallOutcome> callBack(String peer, {required bool video}) =>
      _ref.read(startCallProvider)(peer, video: video);
}
