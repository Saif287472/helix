import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:orbit_ui/orbit_ui.dart';
import 'package:orbit_preview/ported.dart';

/// A key on a wide window, the way the prototype opens it
/// (`App.open` in `js/app.js`): every screen of its `base` is pushed, then
/// the key's own, each into the pane its placement and the pane it was
/// opened from decide (`route`). The window shows the top page of each
/// pane.
///
/// The screens' table is the prototype's `screens.json`; a base screen is
/// drawn by the key whose screen and parameters match it (else the first
/// key of that screen).
final class OrbitWindowComposer {
  OrbitWindowComposer._(this._entries, this._placement);

  /// Reads `prototype/screens.json` beside `orbit/flutter`, or null when it
  /// is not there.
  static OrbitWindowComposer? load() {
    var dir = Directory.current.absolute;
    for (var i = 0; i < 6; i++) {
      final f = File('${dir.path}/orbit/prototype/screens.json');
      final g = File('${dir.path}/prototype/screens.json');
      final file = f.existsSync() ? f : (g.existsSync() ? g : null);
      if (file != null) {
        final d = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
        final defs = d['screenDefs']! as Map<String, Object?>;
        return OrbitWindowComposer._(
          [
            for (final e in d['screens']! as List)
              (e as Map).cast<String, Object?>(),
          ],
          {
            for (final MapEntry(:key, :value) in defs.entries)
              key: ((value! as Map)['placement'] as String?) ?? 'inherit',
          },
        );
      }
      dir = dir.parent;
    }
    return null;
  }

  final List<Map<String, Object?>> _entries;
  final Map<String, String> _placement;

  static const _unboxed = ['call', 'media-viewer'];

  String _place(String screen, Map<String, Object?> params) =>
      screen == 'restore' && params['afterSignIn'] == true
      ? 'full'
      : _placement[screen] ?? 'inherit';

  /// The key that draws [screen] with [params].
  String? _keyFor(String screen, Map<String, Object?> params) {
    final want = jsonEncode(params);
    String? first;
    for (final e in _entries) {
      if (e['screen'] != screen) continue;
      if (!orbitPorted.containsKey(e['key'])) continue;
      first ??= e['key']! as String;
      if (jsonEncode(e['params']) == want) return e['key']! as String;
    }
    return first;
  }

  /// The window for [key] at [width], or null when the key is unknown.
  Widget? build(String key, double width) {
    final entry = _entries.where((e) => e['key'] == key).firstOrNull;
    if (entry == null) return null;
    final wideInfo = width >= orbitInfoBreakpoint;
    final panes = <String, List<String>>{
      'list': [],
      'detail': [],
      'info': [],
      'full': [],
    };
    final screenOf = <String, String>{};
    final paramsOf = <String, Map<String, Object?>>{};
    String? last;
    void push(String screen, Map<String, Object?> params, String k) {
      final from = panes['full']!.isNotEmpty ? 'full' : last;
      final p = _place(screen, params);
      String pane;
      var reset = false;
      if (p == 'full' || p == 'list') {
        pane = p;
      } else if (from == 'full') {
        pane = 'full';
      } else if (p == 'detail') {
        pane = 'detail';
        reset = true;
      } else if (p == 'info') {
        if (from == 'detail') {
          pane = wideInfo ? 'info' : 'detail';
          reset = wideInfo;
        } else if (from == 'info') {
          pane = 'info';
        } else {
          pane = 'detail';
          reset = true;
        }
      } else if (from == 'detail' || from == 'info') {
        pane = from!;
      } else {
        pane = 'detail';
        reset = true;
      }
      if (reset) {
        if (pane == 'detail') panes['detail']!.clear();
        panes['info']!.clear();
      }
      panes[pane]!.add(k);
      screenOf[k] = screen;
      paramsOf[k] = params;
      last = pane;
    }

    for (final b in (entry['base'] as List? ?? const [])) {
      final m = (b as Map).cast<String, Object?>();
      final screen = m['screen']! as String;
      final params = ((m['params'] as Map?) ?? const {})
          .cast<String, Object?>();
      final k = _keyFor(screen, params);
      if (k != null) push(screen, params, '$k#base');
    }
    push(
      entry['screen']! as String,
      ((entry['params'] as Map?) ?? const {}).cast<String, Object?>(),
      key,
    );

    Widget draw(String k) {
      final builder = orbitPorted[k.split('#').first]!;
      return Builder(key: ValueKey(k), builder: builder);
    }

    String? top(String p) => panes[p]!.isEmpty ? null : panes[p]!.last;
    final list = top('list');
    final listScreen = list == null ? null : screenOf[list];
    final listKey = list?.split('#').first;
    final placeholder = listScreen == 'settings-page'
        ? OrbitPlaceholderKind.you
        : listKey == 'calls' ||
              (listScreen == 'home' &&
                  _entries.any(
                    (e) =>
                        e['key'] == listKey &&
                        (e['params'] as Map?)?['tab'] == 'calls',
                  ))
        ? OrbitPlaceholderKind.calls
        : OrbitPlaceholderKind.chats;
    final full = top('full');
    // What is open on the right, for the list to mark.
    final right = panes['detail']!.isEmpty ? null : panes['detail']!.first;
    final current = right == null
        ? null
        : (paramsOf[right]?['id'] as String?) ??
              (screenOf[right] == 'call-detail' ? 'call' : screenOf[right]);
    return OrbitCurrentScope(
      id: current,
      child: OrbitWindowScaffold(
        list: list == null ? const SizedBox.shrink() : draw(list),
        detail: top('detail') == null ? null : draw(top('detail')!),
        detailRoot: panes['detail']!.length <= 1,
        info: top('info') == null ? null : draw(top('info')!),
        infoRoot: panes['info']!.length <= 1,
        full: full == null ? null : draw(full),
        fullBoxed: full != null && !_unboxed.contains(screenOf[full]),
        placeholder: placeholder,
      ),
    );
  }
}
