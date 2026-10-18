import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:orbit_preview/device.dart';
import 'package:orbit_preview/ported.dart';
import 'package:orbit_preview/theme_library.dart';
import 'package:orbit_ui/compare.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Shoot mode: the Flutter half of the compare tool, in the real app.
///
/// The preview app draws ported screens with real fonts and the real engine,
/// so it photographs them too, instead of a widget test (which draws text in
/// its test font unless every font is loaded, and whose fake clock never lets
/// `toImage` finish). Run the built app with:
///
/// ```
/// orbit_preview.exe --shoot startup[,<key>...] [--theme orbit]
///     [--device phone] [--reduce-motion] [--out <dir>] [--html <dir>]
///     [--report <dir>]
/// orbit_preview.exe --gallery [--out <dir>]
/// ```
///
/// `--shoot` writes `<key>.<device>.<theme>.png` per key into `--out`
/// (default `tools/compare/flutter/`), then compares each against the
/// prototype's shot of the same name in `--html` (default
/// `tools/compare/shots/`, which `shoot_html.py` writes) and writes the diff
/// and overlay images, `results.json` and `index.html` into `--report`
/// (default `tools/compare/report/`). `--gallery` writes one PNG per theme
/// card. The app exits when it is done; exit code 1 means something failed,
/// and the reason is printed.
final class ShootRequest {
  ShootRequest._({
    required this.keys,
    required this.gallery,
    required this.theme,
    required this.device,
    required this.reduceMotion,
    required this.out,
    required this.html,
    required this.report,
    required this.scroll,
  });

  /// The request in [args], or null when the app should start normally.
  static ShootRequest? parse(List<String> args) {
    if (!args.contains('--shoot') && !args.contains('--gallery')) return null;
    String? option(String name) {
      final i = args.indexOf(name);
      return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
    }

    final root = _toolsDir();
    final shoot = option('--shoot');
    return ShootRequest._(
      keys: shoot == null
          ? const []
          : shoot.split(',').where((k) => k.isNotEmpty).toList(),
      gallery: args.contains('--gallery'),
      theme: option('--theme') ?? 'orbit',
      device: OrbitDevice.byWireName(option('--device') ?? 'phone'),
      reduceMotion: args.contains('--reduce-motion'),
      out: option('--out') ?? '$root/flutter',
      html: option('--html') ?? '$root/shots',
      report: option('--report') ?? '$root/report',
      scroll: int.parse(option('--scroll') ?? '0'),
    );
  }

  final List<String> keys;
  final bool gallery;
  final String theme;
  final OrbitDevice device;
  final bool reduceMotion;
  final String out;
  final String html;
  final String report;

  /// `--scroll <px>`: like the prototype's `?scroll=`, scrolls the screen's
  /// first scrolling list that far before the shot.
  final int scroll;
}

/// `orbit/flutter/tools/compare`, found from the working directory, so the
/// defaults work from the repository root, `orbit/flutter` or the app folder.
String _toolsDir() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final candidate = Directory('${dir.path}/orbit/flutter/tools/compare');
    if (candidate.existsSync()) return candidate.path.replaceAll(r'\', '/');
    final here = Directory('${dir.path}/tools/compare');
    if (here.existsSync() &&
        File('${dir.path}/tools/compare/shoot_html.py').existsSync()) {
      return here.path.replaceAll(r'\', '/');
    }
    dir = dir.parent;
  }
  return '${Directory.current.path.replaceAll(r'\', '/')}/compare';
}

/// Runs [request], prints what it wrote, and returns the exit code.
Future<int> runShoot(OrbitThemeLibrary library, ShootRequest request) async {
  final stage = ValueNotifier<Widget>(const SizedBox.shrink());
  // A screen that throws draws Flutter's red error box, which would still
  // photograph and score. Any error during a shot fails that shot instead.
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  runApp(_ShootApp(stage: stage));
  var failed = false;

  if (request.keys.isNotEmpty) {
    final tokens = library.byId(request.theme);
    final files = <OrbitShotFile>[];
    for (final key in request.keys) {
      final build = orbitPorted[key];
      if (build == null) {
        stderr.writeln('$key: not ported, so there is nothing to shoot');
        failed = true;
        continue;
      }
      final boundary = GlobalKey();
      stage.value = OrbitShotBoundary(
        shotKey: boundary,
        child: OrbitDeviceSurface(
          device: request.device,
          tokens: tokens,
          reduceMotion: request.reduceMotion,
          child: Builder(builder: build),
        ),
      );
      await _settle();
      if (errors.isNotEmpty) {
        stderr.writeln('$key: the screen threw, so it was not shot:');
        stderr.writeln(errors.first.exceptionAsString());
        errors.clear();
        failed = true;
        continue;
      }
      if (request.scroll > 0) {
        final list = _firstScrollable(boundary.currentContext!);
        if (list == null) {
          stderr.writeln('$key: nothing scrolls, so --scroll does nothing');
        } else {
          list.position.jumpTo(
            request.scroll.toDouble().clamp(0, list.position.maxScrollExtent),
          );
          await _settle();
        }
      }
      final spec = OrbitShotSpec(
        key,
        device: request.device,
        theme: request.theme,
        scroll: request.scroll,
      );
      final image = await captureOrbitShot(boundary, device: request.device);
      // Where every text and drawn box landed, for measuring against the
      // prototype's layout (`<shot>.boxes.txt` beside the PNG).
      File(
        '${request.out}/${spec.fileName.replaceFirst('.png', '.boxes.txt')}',
      ).writeAsStringSync(_boxes(boundary));
      final file = await writeOrbitShot(
        image,
        outDir: request.out,
        fileName: spec.fileName,
      );
      files.add(file);
      stdout.writeln('shot ${spec.fileName} (${file.bytes} bytes)');
    }
    buildOrbitManifest(
      device: request.device,
      theme: request.theme,
      files: files,
    ).write(
      '${request.out}/manifest.json',
      device: request.device,
      theme: request.theme,
    );
    if (!_compare(request, files)) failed = true;
  }

  if (request.gallery) {
    for (final tokens in library.themes) {
      final boundary = GlobalKey();
      stage.value = RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: OrbitDevice.phone.width.toDouble(),
          child: Theme(
            data: OrbitTheme.of(tokens),
            child: Material(
              color: tokens.bg,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: OrbitThemeCard(tokens: tokens),
              ),
            ),
          ),
        ),
      );
      await _settle();
      final object =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await object.toImage();
      final file = await writeOrbitShot(
        image,
        outDir: '${request.out}/gallery',
        fileName: 'gallery-${tokens.meta.id}.png',
      );
      stdout.writeln('shot ${file.path} (${image.width}x${image.height})');
    }
  }
  return failed ? 1 : 0;
}

/// One line per text and per decorated or custom-painted box under
/// [boundary]: its kind, its rectangle in the shot, and the text.
String _boxes(GlobalKey boundary) {
  final root = boundary.currentContext!.findRenderObject()!;
  final out = StringBuffer();
  String f(double v) => v.toStringAsFixed(2);
  void visit(RenderObject o) {
    if (o is RenderBox && o.hasSize) {
      final kind = switch (o) {
        RenderParagraph() => 'text',
        RenderDecoratedBox() => 'box',
        RenderCustomPaint() => 'paint',
        RenderPhysicalShape() || RenderPhysicalModel() => 'material',
        RenderEditable() => 'input',
        _ => null,
      };
      if (kind != null) {
        final at = o.localToGlobal(Offset.zero, ancestor: root);
        final text = switch (o) {
          RenderParagraph() => ' "${o.text.toPlainText()}"',
          RenderEditable() => ' "${o.text?.toPlainText()}"',
          _ => '',
        };
        out.writeln(
          '$kind ${f(at.dx)} ${f(at.dy)} ${f(o.size.width)} '
          '${f(o.size.height)}$text',
        );
      }
    }
    o.visitChildren(visit);
  }

  visit(root);
  return out.toString();
}

/// The first vertical [Scrollable] under [context], depth first.
ScrollableState? _firstScrollable(BuildContext context) {
  ScrollableState? found;
  void visit(Element e) {
    if (found != null) return;
    if (e is StatefulElement && e.state is ScrollableState) {
      final s = e.state as ScrollableState;
      if (s.position.axis == Axis.vertical) {
        found = s;
        return;
      }
    }
    e.visitChildElements(visit);
  }

  (context as Element).visitChildElements(visit);
  return found;
}

/// Lets the stage build, lay out and paint, with fonts and a few frames in.
Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 150));
  for (var i = 0; i < 3; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }
}

/// Compares each shot with the prototype's, and writes the report. False when
/// a prototype shot is missing or a comparison failed.
bool _compare(ShootRequest request, List<OrbitShotFile> files) {
  final jobs = <OrbitCompareJob>[];
  var ok = true;
  for (final file in files) {
    final name = file.path.replaceAll(r'\', '/').split('/').last;
    final html = '${request.html}/$name';
    if (!File(html).existsSync()) {
      stderr.writeln(
        '$name: no prototype shot at $html. Run shoot_html.py first.',
      );
      ok = false;
      continue;
    }
    jobs.add(
      OrbitCompareJob(
        spec: orbitParseShotFileName(name),
        htmlPath: html,
        flutterPath: file.path,
      ),
    );
  }
  if (jobs.isEmpty) return ok;
  final results = compareOrbitJobs(
    jobs,
    outDir: request.report,
    stopOnError: false,
  );
  writeOrbitResultsJson(
    results,
    path: '${request.report}/results.json',
    device: request.device,
    theme: request.theme,
  );
  File(
    '${request.report}/index.html',
  ).writeAsStringSync(_page(sortWorstFirst(results), request.report));
  for (final r in results) {
    if (r.status == OrbitCompareStatus.failed) ok = false;
    stdout.writeln(
      '${r.spec.shortName}: ${r.score == null ? 'failed (${r.reason})' : '${r.score}% of pixels differ'}',
    );
  }
  stdout.writeln('report: ${request.report}/index.html');
  return ok;
}

/// The compare page: per screen, worst first, the two shots side by side, a
/// slider that wipes one over the other, and the difference heat map.
String _page(List<OrbitCompareResult> results, String reportDir) {
  String src(String? path) {
    if (path == null) return '';
    final p = path.replaceAll(r'\', '/');
    // Paths outside the report folder come back absolute; a file:// page
    // needs them as URLs.
    final url = RegExp(r'^[A-Za-z]:/').hasMatch(p) ? 'file:///$p' : p;
    return const HtmlEscape(HtmlEscapeMode.attribute).convert(url);
  }

  final rows = StringBuffer();
  for (final r in results) {
    final name = const HtmlEscape().convert(r.spec.shortName);
    final w = r.width;
    final h = r.height;
    if (r.score == null) {
      rows.writeln(
        '<section><h2>$name <span class="bad">failed</span></h2><p>${const HtmlEscape().convert(r.reason ?? '')}</p></section>',
      );
      continue;
    }
    rows.writeln('''
<section>
  <h2>$name <span class="score">${r.score}% of pixels differ</span></h2>
  <div class="row">
    <figure><figcaption>Prototype</figcaption><img src="${src(r.htmlPath)}" width="$w" height="$h"></figure>
    <figure><figcaption>Flutter</figcaption><img src="${src(r.flutterPath)}" width="$w" height="$h"></figure>
    <figure><figcaption>Wipe: prototype left, Flutter right</figcaption>
      <div class="wipe" style="width:${w}px;height:${h}px">
        <img src="${src(r.htmlPath)}" width="$w" height="$h">
        <img class="top" src="${src(r.flutterPath)}" width="$w" height="$h" style="clip-path:inset(0 0 0 50%)">
      </div>
      <input type="range" min="0" max="100" value="50" aria-label="Wipe position">
    </figure>
    <figure><figcaption>Difference (red is different)</figcaption><img src="${src(r.diffPath)}" width="$w" height="$h"></figure>
  </div>
</section>''');
  }
  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Orbit compare</title>
<style>
  body { font: 14px/1.4 system-ui, sans-serif; margin: 24px; background: #F5F7FA; color: #131722; }
  h1 { font-size: 20px; } h2 { font-size: 16px; margin: 32px 0 8px; }
  .score { font-weight: 400; color: #5B6475; margin-left: 8px; } .bad { color: #C62828; }
  .row { display: flex; flex-wrap: wrap; gap: 16px; align-items: flex-start; }
  figure { margin: 0; } figcaption { font-size: 12px; color: #5B6475; margin-bottom: 4px; }
  img { display: block; box-shadow: 0 0 0 1px #DCE0E8; }
  .wipe { position: relative; } .wipe img { position: absolute; inset: 0; } .wipe .top { box-shadow: none; }
  input[type=range] { width: 100%; margin-top: 6px; }
  p.note { color: #5B6475; max-width: 70ch; }
</style></head><body>
<h1>Orbit compare</h1>
<p class="note">${const HtmlEscape().convert(orbitScoreMeaning)}</p>
$rows
<script>
  document.querySelectorAll('figure').forEach((f) => {
    const range = f.querySelector('input[type=range]');
    const top = f.querySelector('.wipe .top');
    if (range && top) range.addEventListener('input', () => { top.style.clipPath = 'inset(0 0 0 ' + range.value + '%)'; });
  });
</script>
</body></html>
''';
}

/// The stage: whatever is being photographed, at its own size, from the top
/// left, whatever size the window happens to be.
class _ShootApp extends StatelessWidget {
  const _ShootApp({required this.stage});

  final ValueNotifier<Widget> stage;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    // An Overlay, because a builder-only MaterialApp has no Navigator to
    // provide one, and tooltips and menus need it.
    builder: (context, _) => Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => ValueListenableBuilder<Widget>(
            valueListenable: stage,
            builder: (context, child, _) => OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        ),
      ],
    ),
  );
}
