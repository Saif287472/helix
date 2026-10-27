import 'package:flutter/material.dart';
import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/list_rows.dart';
import 'package:orbit_ui/src/components/overlays.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// How many other people a group call can ring: a room holds four.
const int orbitGroupCallInvites = 3;

/// A sheet for choosing who a group call rings, when the group has more
/// members than a room holds. Picks up to [orbitGroupCallInvites] of
/// [candidates]; answers their ids, or null when the sheet was dismissed.
Future<List<String>?> showOrbitGroupCallPicker(
  BuildContext context, {
  required List<HelixPersonItem> candidates,
  required bool video,
}) async {
  List<String>? chosen;
  await showOrbitSheet(
    context,
    title: video ? 'Start a group video call' : 'Start a group voice call',
    text: 'A group call holds up to four people. Choose up to three to ring.',
    body: _CallPicker(
      candidates: candidates,
      video: video,
      onDone: (ids) => chosen = ids,
    ),
  );
  return chosen;
}

class _CallPicker extends StatefulWidget {
  const _CallPicker({
    required this.candidates,
    required this.video,
    required this.onDone,
  });

  final List<HelixPersonItem> candidates;
  final bool video;
  final ValueChanged<List<String>> onDone;

  @override
  State<_CallPicker> createState() => _CallPickerState();
}

class _CallPickerState extends State<_CallPicker> {
  final _picked = <String>[];

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id) && _picked.length < orbitGroupCallInvites) {
      _picked.add(id);
    }
  });

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final full = _picked.length >= orbitGroupCallInvites;
    // The sheet scrolls its body itself: the list just takes its height.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in widget.candidates)
          Semantics(
            selected: _picked.contains(p.id),
            child: OrbitListRow(
              title: p.names.display,
              leading: OrbitAvatar(avatar: p.avatar, size: 40),
              minHeight: 56,
              trailing: _picked.contains(p.id)
                  ? Icon(Icons.check_circle, size: 22, color: t.accent)
                  : Icon(
                      Icons.circle_outlined,
                      size: 22,
                      color: full ? t.ink4 : t.controlLine,
                    ),
              onTap: full && !_picked.contains(p.id)
                  ? null
                  : () => _toggle(p.id),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: OrbitButton(
            label: _picked.isEmpty
                ? 'Choose who to call'
                : 'Call ${_picked.length}',
            icon: widget.video ? OrbitIcons.videoCamera : OrbitIcons.phone,
            block: true,
            onPressed: _picked.isEmpty
                ? null
                : () {
                    widget.onDone(List.of(_picked));
                    Navigator.of(context).pop();
                  },
          ),
        ),
      ],
    );
  }
}
