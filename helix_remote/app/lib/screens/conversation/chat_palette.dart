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
      page: Color(0xFF0B1417),
      appBar: Color(0xFF0B1114),
      onAppBar: Colors.white,
      inputBar: Color(0xFF0B1417),
      input: Color(0xFF1F2C34),
      incoming: Color(0xFF1F2C34),
      outgoing: Color(0xFF005C4B),
      incomingTime: Color(0xFF98A4AA),
      outgoingTime: Color(0xFFB8D5C8),
      dateChip: Color(0xE61C252B),
      dateChipText: Color(0xFFD7DEE2),
      accent: Color(0xFF00A884),
      readTick: Color(0xFF53BDEB),
    );
  }
  return ConversationPalette(
    page: const Color(0xFFEDE7DE),
    appBar: scheme.surface,
    onAppBar: scheme.onSurface,
    inputBar: const Color(0xFFEDE7DE),
    input: Colors.white,
    incoming: Colors.white,
    outgoing: const Color(0xFFD9FFD2),
    incomingTime: const Color(0xFF667781),
    outgoingTime: const Color(0xFF667781),
    dateChip: const Color(0xF7FFFFFF),
    dateChipText: const Color(0xFF667781),
    accent: const Color(0xFF00A884),
    readTick: const Color(0xFF34B7F1),
  );
}
