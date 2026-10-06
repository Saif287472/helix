import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show TransferPhase;

/// What a media bubble's tap did, so the screen can follow up.
enum MediaTap {
  /// The file is here: open the viewer or the document.
  open,

  /// A download or retry was started.
  fetching,

  /// A running transfer was cancelled.
  cancelled,
}

/// Media taps and the actions on a viewed file.
final class MediaActions {
  MediaActions(this._ref);

  final Ref _ref;

  Future<ChatGateway> get _gateway => _ref.read(chatGatewayProvider.future);

  /// What a tap on [part] should do: open it when it is on the device,
  /// download it (or retry a failed one) when it is not, cancel a transfer
  /// that is running.
  Future<MediaTap> tap(MediaPart part, {required int messageRowid}) async {
    final gateway = await _gateway;
    final phase = part.view?.phase;
    if (part.ready) return MediaTap.open;
    if (phase == TransferPhase.queued || phase == TransferPhase.active) {
      await gateway.cancelTransfer(part.id);
      return MediaTap.cancelled;
    }
    if (part.row.mediaId.isEmpty) {
      // An upload that failed: retrying the message retries its uploads.
      await gateway.retryTransfer(messageRowid);
    } else {
      await gateway.downloadNow(part.id);
    }
    return MediaTap.fetching;
  }

  /// Hands the file of [part] to the system share sheet: that is how a
  /// document is opened in another app, or a video played, on a phone.
  /// False when the file is not on the device.
  Future<bool> share(MediaPart part) async {
    final gateway = await _gateway;
    final path = await gateway.localPathOf(part.id);
    if (path == null) return false;
    await _ref
        .read(fileActionsProvider)
        .shareFile(
          path: path,
          name: part.row.name ?? 'file',
          mime: part.row.mime,
        );
    return true;
  }
}

final mediaActionsProvider = Provider<MediaActions>(MediaActions.new);

/// What the viewer shows around the picture.
@immutable
class ViewerMeta {
  const ViewerMeta({
    required this.senderName,
    required this.timeLabel,
    this.caption = '',
    this.viewOnce = false,
    this.outgoing = false,
    this.alreadyOpened = false,
  });

  final String senderName;
  final String timeLabel;
  final String caption;

  /// A view-once message: it can be looked at once, and then it is gone.
  final bool viewOnce;
  final bool outgoing;

  /// A view-once message that was opened before (so it cannot be shown).
  final bool alreadyOpened;
}

final viewerMetaProvider = FutureProvider.autoDispose.family<ViewerMeta?, int>((
  ref,
  rowid,
) async {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(peopleDirectoryProvider.future);
  final row = await gateway.message(rowid);
  if (row == null) return null;
  return ViewerMeta(
    senderName: row.outgoing ? 'You' : people.displayOf(row.sender),
    timeLabel: formatDateTime(row.sentAt, ref.read(clockProvider)()),
    caption: row.body ?? '',
    viewOnce: row.viewOnceState != null,
    outgoing: row.outgoing,
    alreadyOpened: !row.outgoing && row.viewOnceState == ViewOnceState.opened,
  );
});

/// Opens and closes a view-once message: `open` marks it opened and tells the
/// sender; `close` deletes the file for good.
final class ViewOnceSession {
  ViewOnceSession(this._ref, this.rowid);

  final Ref _ref;
  final int rowid;
  bool _opened = false;

  Future<void> open() async {
    if (_opened) return;
    _opened = true;
    final gateway = await _ref.read(chatGatewayProvider.future);
    await gateway.openViewOnce(rowid);
  }

  Future<void> close() async {
    if (!_opened) return;
    final gateway = await _ref.read(chatGatewayProvider.future);
    try {
      await gateway.consumeViewOnce(rowid);
    } on Object {
      // Already consumed.
    }
  }
}

/// Not auto-disposed: `close` runs after the viewer screen is gone, and must
/// still be able to reach the engine.
final viewOnceSessionProvider = Provider.family<ViewOnceSession, int>(
  ViewOnceSession.new,
);
