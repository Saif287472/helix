import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/call_log.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: one person's calls, who it was and every call with them,
/// newest first, with buttons to call again, drawn by `orbit_ui`'s Call
/// details (`contracts/calls.md`). Opened from a Calls row and from a
/// `helix://call/…` link.
class CallDetailScreen extends ConsumerWidget {
  const CallDetailScreen({super.key, required this.callId});

  final String callId;

  static orbit.CallLogDirection _directionOf(CallLogDirection d) => switch (d) {
    CallLogDirection.incoming => orbit.CallLogDirection.incoming,
    CallLogDirection.outgoing => orbit.CallLogDirection.outgoing,
    CallLogDirection.missed => orbit.CallLogDirection.missed,
    CallLogDirection.declined => orbit.CallLogDirection.declined,
    CallLogDirection.failed => orbit.CallLogDirection.failed,
    CallLogDirection.cancelled => orbit.CallLogDirection.cancelled,
    CallLogDirection.noAnswer => orbit.CallLogDirection.noAnswer,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(callDetailProvider(callId));
    final value = detail.value;
    final blocksMe = value == null
        ? false
        : ref.watch(callPeerBlocksMeProvider(value.peer)).value ?? false;
    final actions = ref.read(callLogActionsProvider);

    Future<String?> call({required bool video}) async {
      final peer = value?.peer;
      if (peer == null) return null;
      final outcome = await actions.callBack(peer, video: video);
      return outcome.started
          ? null
          : outcome.message ?? 'The call could not be placed.';
    }

    return orbit.CallDetailScreen(
      model: orbit.CallDetailModel(
        status: switch (detail) {
          AsyncError() => orbit.CallDetailStatus.error,
          AsyncData() when value == null => orbit.CallDetailStatus.notFound,
          AsyncData() => orbit.CallDetailStatus.ready,
          _ => orbit.CallDetailStatus.loading,
        },
        title: value?.title ?? '',
        subtitle: value?.subtitle,
        avatar: value?.avatar ?? const orbit.HelixAvatarModel(name: ''),
        rows: [
          for (final r in value?.rows ?? const <CallDetailRow>[])
            orbit.CallDetailRowModel(
              callId: r.callId,
              direction: _directionOf(r.direction),
              label: r.label,
              timeLabel: r.timeLabel,
              durationLabel: r.durationLabel,
              spokenDuration: r.spokenDuration,
              video: r.video,
            ),
        ],
        // Someone who blocked you: no call buttons, and why (ADR-030).
        canCall: !blocksMe,
        blockedReason: blocksMe ? CallCopy.blockedYou(value.title) : null,
      ),
      actions: orbit.CallDetailActions(
        voiceCall: () => call(video: false),
        videoCall: () => call(video: true),
        openContact: value == null
            ? null
            : () => context.push(PeoplePaths.person(value.peer)),
        deleteAll: value == null
            ? null
            : () async {
                await actions.delete([for (final r in value.rows) r.callId]);
                if (context.mounted) await Navigator.of(context).maybePop();
              },
        retry: () => ref.invalidate(callDetailProvider(callId)),
      ),
    );
  }
}
