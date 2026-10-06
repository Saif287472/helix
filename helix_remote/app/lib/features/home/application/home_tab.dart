import 'package:flutter/material.dart';

/// The three tabs, in the order they appear. Home is Chats, Calls, Settings -
/// there is no Contacts tab, because there are no contact requests: anybody
/// can message or call anybody who has not blocked them.
enum HomeTab {
  chats('Chats', Icons.chat_bubble_outline, Icons.chat_bubble),
  calls('Calls', Icons.call_outlined, Icons.call),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const HomeTab(this.label, this.icon, this.selectedIcon);

  /// Plain English, set here once rather than at each use site.
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
