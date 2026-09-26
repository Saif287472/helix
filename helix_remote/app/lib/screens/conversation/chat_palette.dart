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
  // Light only - see HelixThemes. The near-black chat palette that used to be
  // returned for a dark theme is removed rather than left behind a branch
  // nothing can reach, because these are the surfaces a conversation is read
  // against and a stray near-black one is exactly what the product is avoiding.
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
