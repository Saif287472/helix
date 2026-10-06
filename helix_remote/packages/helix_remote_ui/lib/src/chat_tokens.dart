part of '../helix_remote_ui.dart';

/// Colours that belong to the conversation surface: the wallpaper the
/// bubbles sit on and the bubbles themselves.
///
/// These are fixed fills rather than colour-scheme roles on purpose. A chat is
/// read against a warm paper-like page, and outgoing/incoming bubbles must stay
/// distinguishable by colour alone in both the default and the high-contrast
/// theme. Everything else in the chat components (unread badge, send button,
/// quote bar, links) comes from `Theme.of(context).colorScheme`.
abstract final class HelixChatColors {
  /// The page behind the bubbles (and behind the composer).
  static const page = HelixColorTokens.cFFEDE7DE;

  /// An outgoing bubble.
  static const outgoing = HelixColorTokens.cFFD9FFD2;

  /// An incoming bubble.
  static const incoming = HelixScrimColors.onBackdrop;

  /// Time, "edited" and other metadata inside a bubble. Darker than the
  /// legacy grey so it reads at 4.5:1 on both bubble fills.
  static const metaText = Color(0xFF54656F);

  /// The floating pill behind a date separator or system notice.
  static const notice = HelixColorTokens.cF7FFFFFF;

  /// The "read" double tick.
  static const readTick = HelixColorTokens.cFF34B7F1;

  /// Voice-note waveform bars that have not been played yet / the track.
  static const waveformIdle = HelixColorTokens.cFF98A4AA;
}

/// Sizes shared by the chat components. Keeping them here is what lets a list
/// give `ListView.builder` an exact `itemExtent` instead of measuring.
abstract final class HelixChatMetrics {
  /// Height of a chat-list row at text scale 1.0. Use
  /// [HelixChatListTile.extentFor] for the scaled value.
  static const chatTileHeight = 72.0;

  /// The tap target minimum from the accessibility rules.
  static const minTarget = 48.0;

  /// Largest share of the row a bubble may take.
  static const bubbleMaxWidthFactor = 0.8;

  /// Width reserved on the tail side of a bubble.
  static const bubbleTail = 6.0;

  static const bubbleRadius = 12.0;

  /// Space between two bubbles of the same run, and between runs.
  static const bubbleGapSameRun = 2.0;
  static const bubbleGapNewRun = 8.0;

  /// Two messages from the same sender further apart than this start a new run.
  static const runGapMs = 5 * 60 * 1000;

  /// Voice-note waveform bar count.
  static const waveformBars = 36;
}
