import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/message_info.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: "Message info", your message as sent, when it was sent, and
/// when each person got it and read it, drawn by `orbit_ui`'s page.
class MessageInfoScreen extends ConsumerWidget {
  const MessageInfoScreen({super.key, required this.rowid});

  final int rowid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(messageInfoProvider(rowid));
    final value = info.value;
    final model = switch (info) {
      AsyncData() when value == null => const orbit.MessageInfoModel(
        loadState: orbit.MessageInfoState.notFound,
      ),
      AsyncData() => _model(ref, value!),
      AsyncError() => const orbit.MessageInfoModel(
        loadState: orbit.MessageInfoState.error,
      ),
      _ => const orbit.MessageInfoModel(
        loadState: orbit.MessageInfoState.loading,
      ),
    };
    return orbit.MessageInfoScreen(
      model: model,
      actions: orbit.MessageInfoActions(
        onRetry: () => ref.invalidate(messageInfoProvider(rowid)),
      ),
    );
  }

  orbit.MessageInfoModel _model(WidgetRef ref, MessageInfo info) {
    var message = info.message;
    if (message != null && info.hasMedia) {
      // A photo, a file or a voice message: its attachments, as the chat
      // draws them.
      final parts = ref.watch(messageMediaProvider(rowid)).value;
      final placeholder = message.content;
      if (parts != null) {
        message = message.copyWith(
          content: mediaContentOf(
            rowid: rowid,
            caption: placeholder is orbit.HelixMediaContent
                ? placeholder.caption
                : '',
            parts: parts,
          ),
        );
      }
    }
    return orbit.MessageInfoModel(
      message: message,
      sentLabel: info.sentLabel,
      isGroup: info.isGroup,
      edits: [
        for (final e in info.edits)
          orbit.MessageEditItem(
            text: e.text,
            whenLabel: e.whenLabel,
            current: e.current,
          ),
      ],
      recipients: [
        for (final line in info.lines)
          orbit.ReceiptItem(
            name: line.name,
            avatar: line.avatar,
            readLabel: line.readLabel == null ? null : 'Read ${line.readLabel}',
            deliveredLabel: line.deliveredLabel == null
                ? null
                : 'Delivered ${line.deliveredLabel}',
          ),
      ],
    );
  }
}
