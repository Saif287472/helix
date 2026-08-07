import 'package:helix_remote_ui/helix_remote_ui.dart';
import 'package:flutter/material.dart';

/// Conversation-specific colours shared by the screen and its message tiles.
class ConversationPalette {
  const ConversationPalette({
    required this.page,
    required this.appBar,
    required this.onAppBar,
    required this.inputBar,
    required this.input,
    required this.incoming,
    required this.outgoing,
    required this.incomingTime,
    required this.outgoingTime,
    required this.dateChip,
    required this.dateChipText,
    required this.accent,
    required this.readTick,
  });

  final Color page;
  final Color appBar;
  final Color onAppBar;
  final Color inputBar;
  final Color input;
  final Color incoming;
  final Color outgoing;
  final Color incomingTime;
  final Color outgoingTime;
  final Color dateChip;
  final Color dateChipText;
  final Color accent;
  final Color readTick;
}

ConversationPalette conversationPalette(ThemeData theme) {
  final scheme = theme.colorScheme;
  if (theme.brightness == Brightness.dark) {
    return const ConversationPalette(
      page: HelixColorTokens.cFF0B1417,
      appBar: HelixColorTokens.cFF0B1114,
      onAppBar: HelixScrimColors.onBackdrop,
      inputBar: HelixColorTokens.cFF0B1417,
      input: HelixColorTokens.cFF1F2C34,
      incoming: HelixColorTokens.cFF1F2C34,
      outgoing: HelixColorTokens.cFF005C4B,
      incomingTime: HelixColorTokens.cFF98A4AA,
      outgoingTime: HelixColorTokens.cFFB8D5C8,
      dateChip: HelixColorTokens.cE61C252B,
      dateChipText: HelixColorTokens.cFFD7DEE2,
      accent: HelixColorTokens.cFF00A884,
      readTick: HelixColorTokens.cFF53BDEB,
    );
  }
  return ConversationPalette(
    page: HelixColorTokens.cFFEDE7DE,
    appBar: scheme.surface,
    onAppBar: scheme.onSurface,
    inputBar: HelixColorTokens.cFFEDE7DE,
    input: HelixScrimColors.onBackdrop,
    incoming: HelixScrimColors.onBackdrop,
    outgoing: HelixColorTokens.cFFD9FFD2,
    incomingTime: HelixColorTokens.cFF667781,
    outgoingTime: HelixColorTokens.cFF667781,
    dateChip: HelixColorTokens.cF7FFFFFF,
    dateChipText: HelixColorTokens.cFF667781,
    accent: HelixColorTokens.cFF00A884,
    readTick: HelixColorTokens.cFF34B7F1,
  );
}
