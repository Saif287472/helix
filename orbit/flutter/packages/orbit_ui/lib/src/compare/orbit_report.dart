/// Reading the other half's manifest, comparing every pair, and writing the
/// three artefacts and the results JSON the compare page reads.
///
/// Two rules run through all of it:
///
/// - **Nothing is invented.** A missing PNG, an unreadable PNG or two different
///   sizes is an error. There is no resize, no crop and no "skip quietly", and
///   a failed comparison never carries a score.
/// - **The output is a pure function of the input.** No timestamps, no machine
///   name, no map iteration order and no random anything, so re-running a batch
///   that has not changed produces the same bytes in `results.json` and shows
///   up as an empty diff in git.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:orbit_ui/src/compare/orbit_artefacts.dart';
import 'package:orbit_ui/src/compare/orbit_devices.dart';
import 'package:orbit_ui/src/compare/orbit_diff.dart';
import 'package:orbit_ui/src/compare/orbit_png.dart';
import 'package:orbit_ui/src/compare/orbit_shot.dart';

/// The version of the results shape, so a stale `results.json` from an older
/// tool is recognisable rather than silently misread.
const int orbitCompareJsonFormat = 1;

/// One pair of PNGs to compare: the prototype's, and the Flutter render's.
final class OrbitCompareJob {
  const OrbitCompareJob({
    required this.spec,
    required this.htmlPath,
    required this.flutterPath,
  });

  final OrbitShotSpec spec;
  final String htmlPath;
  final String flutterPath;
}

/// Whether a comparison happened.
///
/// There is deliberately no "skipped": if a comparison did not happen it is
/// [failed], and it carries no score.
enum OrbitCompareStatus {
  compared,
  failed;

  String get wire => name;
}

/// One row of `results.json`.
final class OrbitCompareResult {
  OrbitCompareResult.compared({
    required this.spec,
    required this.diff,
    required this.htmlPath,
    required this.flutterPath,
    required this.diffPath,
    required this.overlayPath,
    required this.overlayMix,
  }) : status = OrbitCompareStatus.compared,
       reason = null;

  OrbitCompareResult.failed({
    required this.spec,
    required this.reason,
    required this.htmlPath,
    required this.flutterPath,
  }) : status = OrbitCompareStatus.failed,
       diff = null,
       diffPath = null,
       overlayPath = null,
       overlayMix = 0.5;

  final OrbitShotSpec spec;
  final OrbitCompareStatus status;

  /// Null exactly when [status] is [OrbitCompareStatus.failed]. A result with a
  /// status and no diff is not something this tool will write.
  final OrbitImageDiff? diff;

  /// Why the comparison did not happen. Empty for a comparison that did.
  final String? reason;

  /// Paths relative to the directory `results.json` is in, with forward
  /// slashes, so the compare page can load them with a plain relative URL on
  /// every platform.
  final String? htmlPath;
  final String? flutterPath;
  final String? diffPath;
  final String? overlayPath;

  /// How much of the Flutter render is in [overlayPath]. Recorded so the page
  /// can label the picture, and so a regenerated overlay is reproducible.
  final double overlayMix;

  int get width => spec.device.width;
  int get height => spec.device.height;

  /// The score, or null when the comparison did not happen.
  double? get score => diff?.roundedScore;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'key': spec.key,
      'device': spec.device.wireName,
      'theme': spec.theme,
      'scroll': spec.scroll,
      'width': width,
      'height': height,
      'status': status.wire,
      'html': htmlPath,
      'flutter': flutterPath,
    };
    final d = diff;
    if (d == null) {
      // No score key at all, not `"score": null`. The page must not be able to
      // read a number where there was no comparison.
      json['reason'] = reason ?? '';
      return json;
    }
    json.addAll(<String, Object?>{
      'score': d.roundedScore,
      'differingPixels': d.differingPixels,
      'totalPixels': d.totalPixels,
      'differingChannels': d.differingChannels,
      'maxChannelDelta': d.maxChannelDelta,
      'meanChannelDelta': double.parse(d.meanChannelDelta.toStringAsFixed(4)),
      'diff': diffPath,
      'overlay': overlayPath,
      'overlayMix': overlayMix,
    });
    return json;
  }
}

/// The words that go in `results.json` so nobody has to guess what the number
/// means or what counts as good. The compare page shows it near the score.
const String orbitScoreMeaning =
    'Percent of pixels that are not byte-identical between the prototype '
    'screenshot and the Flutter render. Chrome and Flutter rasterise text and '
    'blend colours differently, so a screen that is correct to the eye still '
    'scores above zero. The score flags a screen for a person to look at; it '
    'is not a pass mark, and the compare page sorts worst first.';

/// Compares one pair and writes its heat map and overlay under [outDir].
///
/// Throws [OrbitCompareException] if anything is wrong with either side. It
/// never returns a partial result: a comparison that did not happen has no
/// artefacts, because a heat map of nothing would sit on the compare page
/// looking like a measurement.
OrbitCompareResult compareOrbitJob(
  OrbitCompareJob job, {
  required String outDir,
  double overlayMix = 0.5,
}) {
  final prototype = flattenOrbitImage(
    readOrbitPngFile(job.htmlPath, name: 'prototype'),
  );
  final flutter = flattenOrbitImage(
    readOrbitPngFile(job.flutterPath, name: 'flutter'),
  );

  final diff = compareOrbitImages(
    prototype,
    flutter,
    leftName: 'the prototype (${job.htmlPath})',
    rightName: 'the Flutter render (${job.flutterPath})',
  );

  // One delta per pixel, for the heat map's ramp.
  final deltas = Uint8List(diff.width * diff.height);
  for (var p = 0; p < deltas.length; p++) {
    final o = p * 4;
    var delta = 0;
    for (var c = 0; c < 4; c++) {
      final d = (prototype.pixels[o + c] - flutter.pixels[o + c]).abs();
      if (d > delta) delta = d;
    }
    deltas[p] = delta;
  }

  final heat = orbitDiffHeatMap(prototype, flutter, deltaOf: (i) => deltas[i]);
  final overlay = orbitOverlay(prototype, flutter, mix: overlayMix);

  final diffPath = _writePng(outDir, 'diff', job.spec.fileName, heat);
  final overlayPath = _writePng(outDir, 'overlay', job.spec.fileName, overlay);

  return OrbitCompareResult.compared(
    spec: job.spec,
    diff: diff,
    htmlPath: _relative(job.htmlPath, outDir),
    flutterPath: _relative(job.flutterPath, outDir),
    diffPath: diffPath,
    overlayPath: overlayPath,
    overlayMix: overlayMix,
  );
}

/// Compares many pairs.
///
/// [stopOnError] is true by default, which is the loud behaviour: the first
/// missing or mismatched file throws and the run stops. Turning it off records
/// the failure in the results so one bad shot does not hide the other 235 - but
/// a failed row still has no score, and the caller is expected to look at the
/// statuses (the report test asserts none failed).
List<OrbitCompareResult> compareOrbitJobs(
  List<OrbitCompareJob> jobs, {
  required String outDir,
  double overlayMix = 0.5,
  bool stopOnError = true,
}) {
  final results = <OrbitCompareResult>[];
  for (final job in jobs) {
    try {
      results.add(compareOrbitJob(job, outDir: outDir, overlayMix: overlayMix));
    } on OrbitCompareException catch (e) {
      if (stopOnError) rethrow;
      results.add(
        OrbitCompareResult.failed(
          spec: job.spec,
          reason: e.message,
          htmlPath: _relative(job.htmlPath, outDir),
          flutterPath: _relative(job.flutterPath, outDir),
        ),
      );
    }
  }
  return results;
}

/// Sorts worst first, then by key, so the list is stable for two runs that
/// found the same scores, and so the top of the page is always the screen with
/// the most to look at.
List<OrbitCompareResult> sortWorstFirst(Iterable<OrbitCompareResult> results) {
  final sorted = List<OrbitCompareResult>.of(results);
  sorted.sort((a, b) {
    final sa = a.score;
    final sb = b.score;
    if (sa == null && sb == null) {
      return a.spec.shortName.compareTo(b.spec.shortName);
    }
    if (sa == null) return 1;
    if (sb == null) return -1;
    final byScore = sb.compareTo(sa);
    return byScore != 0
        ? byScore
        : a.spec.shortName.compareTo(b.spec.shortName);
  });
  return sorted;
}

/// Writes `results.json` next to the artefacts, and returns its path.
///
/// [scope] is the device and theme the batch was shot at, which goes at the top
/// so the page can label the run without reading every row.
String writeOrbitResultsJson(
  List<OrbitCompareResult> results, {
  required String path,
  required OrbitDevice device,
  required String theme,
  double overlayMix = 0.5,
}) {
  final sorted = sortWorstFirst(results);
  final compared = sorted.where((r) => r.status == OrbitCompareStatus.compared);
  final failed = sorted.where((r) => r.status == OrbitCompareStatus.failed);
  final json = <String, Object?>{
    'tool': 'compare_dart',
    'format': orbitCompareJsonFormat,
    'device': device.wireName,
    'theme': theme,
    'size': <int>[device.width, device.height],
    'overlayMix': overlayMix,
    'scoreMeaning': orbitScoreMeaning,
    'sort': 'worst first',
    'totals': <String, Object?>{
      'compared': compared.length,
      'failed': failed.length,
      'worst': sorted.isEmpty || sorted.first.score == null
          ? null
          : sorted.first.spec.shortName,
    },
    'results': <Map<String, Object?>>[for (final r in sorted) r.toJson()],
  };
  final file = File(path);
  file.parent.createSync(recursive: true);
  // Two-space indent and no trailing newline games: the file is meant to be
  // read by a person when something looks wrong.
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(json)}\n',
  );
  return path;
}

// ---------------------------------------------------------------------------
// Manifests
// ---------------------------------------------------------------------------

/// One row of either half's `manifest.json`.
///
/// `shoot_html.py` writes this shape and so does the Flutter render, which is
/// the point: the report reads one class for both sides and cannot start
/// treating them differently by accident.
final class OrbitManifestShot {
  const OrbitManifestShot({
    required this.spec,
    required this.file,
    required this.ok,
    required this.reason,
    required this.width,
    required this.height,
    required this.bytes,
  });

  /// Parses one row, from either half.
  ///
  /// [file] is required and drives [spec]; a row whose file name does not
  /// follow the agreed pattern is an error, because that is how a device or a
  /// theme id has drifted apart between the halves.
  factory OrbitManifestShot.fromJson(Map<String, Object?> json) {
    final file = json['file'];
    if (file is! String) {
      throw FormatException('a manifest row has no file name: $json');
    }
    final width = json['width'];
    final height = json['height'];
    if (width is! int || height is! int) {
      throw FormatException('$file: a manifest row has no pixel size');
    }
    return OrbitManifestShot(
      spec: orbitParseShotFileName(file),
      file: file,
      ok: json['ok'] is bool ? json['ok']! as bool : true,
      reason: json['reason'] is String ? json['reason']! as String : '',
      width: width,
      height: height,
      bytes: json['bytes'] is int ? json['bytes']! as int : 0,
    );
  }

  final OrbitShotSpec spec;
  final String file;
  final bool ok;
  final String reason;
  final int width;
  final int height;
  final int bytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': spec.key,
    'file': file,
    'ok': ok,
    'reason': reason,
    'width': width,
    'height': height,
    'bytes': bytes,
  };
}

/// A `manifest.json` from either half.
final class OrbitShotManifest {
  OrbitShotManifest({
    required this.tool,
    required this.shots,
    this.device,
    this.theme,
  });

  /// Reads either half's manifest.
  ///
  /// Throws [FormatException] for a file that is not a manifest, and
  /// [OrbitCompareException] for one that is but names a device this build
  /// does not have.
  factory OrbitShotManifest.read(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw OrbitCompareException(
        'no manifest at $path. Run the HTML half first '
        '(python orbit/flutter/tools/compare/shoot_html.py --all).',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw OrbitCompareException('$path is not JSON: ${e.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw OrbitCompareException('$path is not a manifest object');
    }
    final rawShots = decoded['shots'];
    if (rawShots is! List) {
      throw OrbitCompareException('$path has no shots list');
    }
    final deviceName = decoded['device'];
    final themeName = decoded['theme'];
    final toolName = decoded['tool'];
    return OrbitShotManifest(
      tool: toolName is String ? toolName : 'unknown',
      device: deviceName is String ? OrbitDevice.byWireName(deviceName) : null,
      theme: themeName is String ? themeName : null,
      shots: [
        for (final row in rawShots)
          OrbitManifestShot.fromJson(Map<String, Object?>.from(row! as Map)),
      ],
    );
  }

  /// Which half wrote this. `shoot_html` or `shoot_flutter`.
  final String tool;

  final OrbitDevice? device;
  final String? theme;
  final List<OrbitManifestShot> shots;

  /// Writes the manifest, in the shape `shoot_html.py` writes.
  ///
  /// There is deliberately no `generated` timestamp: a second run of the same
  /// batch must produce the same bytes, so `git diff` shows only what actually
  /// changed on screen. The HTML half's own manifest does carry one; this
  /// simply does not pretend to be that tool.
  String write(
    String path, {
    required OrbitDevice device,
    required String theme,
  }) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final json = <String, Object?>{
      'tool': tool,
      'device': device.wireName,
      'theme': theme,
      'deviceSize': <int>[device.width, device.height],
      'shots': <Map<String, Object?>>[for (final shot in shots) shot.toJson()],
    };
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(json)}\n',
    );
    return path;
  }
}

/// Builds the Flutter half's manifest from the files the render wrote.
///
/// It is written in exactly the shape `shoot_html.py` writes, so
/// [OrbitShotManifest.read] reads either side with the same class and the
/// report cannot start treating them differently.
OrbitShotManifest buildOrbitManifest({
  required OrbitDevice device,
  required String theme,
  required List<OrbitShotFile> files,
  String tool = 'shoot_flutter',
}) => OrbitShotManifest(
  tool: tool,
  device: device,
  theme: theme,
  shots: [
    for (final file in files)
      OrbitManifestShot(
        spec: orbitParseShotFileName(file.path.replaceAll(r'\', '/')),
        file: file.path.replaceAll(r'\', '/').split('/').last,
        ok: true,
        reason: '',
        width: file.image.width,
        height: file.image.height,
        bytes: file.bytes,
      ),
  ],
);

/// Pairs the two manifests into the jobs to compare.
///
/// Only shots that succeeded on **both** sides are paired, and a half having
/// taken the shot is not optional: a Flutter render that exists with no
/// prototype shot behind it is a key the port has not reached, and the compare
/// page must not show it as if it had been compared. The missing halves are
/// returned separately so the caller can say what was not compared and why
/// instead of the set quietly shrinking.
OrbitCompareBatch planOrbitBatch({
  required OrbitShotManifest html,
  required OrbitShotManifest flutter,
  required String htmlDir,
  required String flutterDir,
  OrbitDevice? device,
  String? theme,
}) {
  final flutterByKey = <OrbitShotSpec, OrbitManifestShot>{
    for (final shot in flutter.shots)
      if (shot.ok) shot.spec: shot,
  };
  final jobs = <OrbitCompareJob>[];
  final missing = <OrbitCompareMissing>[];
  final htmlSpecs = <OrbitShotSpec>{};
  for (final shot in html.shots) {
    if (!shot.ok) {
      missing.add(
        OrbitCompareMissing(
          spec: shot.spec,
          side: 'prototype',
          reason: shot.reason.isEmpty ? 'the shot failed' : shot.reason,
        ),
      );
      continue;
    }
    htmlSpecs.add(shot.spec);
    if (device != null && shot.spec.device != device) continue;
    if (theme != null && shot.spec.theme != theme) continue;
    final counterpart = flutterByKey[shot.spec];
    if (counterpart == null) {
      missing.add(
        OrbitCompareMissing(
          spec: shot.spec,
          side: 'flutter',
          reason: 'no Flutter render of this key at this device and theme',
        ),
      );
      continue;
    }
    jobs.add(
      OrbitCompareJob(
        spec: shot.spec,
        htmlPath: _join(htmlDir, shot.file),
        flutterPath: _join(flutterDir, counterpart.file),
      ),
    );
  }
  for (final spec in flutterByKey.keys) {
    if (!htmlSpecs.contains(spec)) {
      missing.add(
        OrbitCompareMissing(
          spec: spec,
          side: 'prototype',
          reason: 'the Flutter render has no prototype shot behind it',
        ),
      );
    }
  }
  jobs.sort((a, b) => a.spec.shortName.compareTo(b.spec.shortName));
  missing.sort((a, b) {
    final byName = a.spec.shortName.compareTo(b.spec.shortName);
    return byName != 0 ? byName : a.side.compareTo(b.side);
  });
  return OrbitCompareBatch(jobs: jobs, missing: missing);
}

/// A screen state one side has and the other does not.
final class OrbitCompareMissing {
  const OrbitCompareMissing({
    required this.spec,
    required this.side,
    required this.reason,
  });

  final OrbitShotSpec spec;

  /// `prototype` or `flutter`.
  final String side;

  final String reason;

  @override
  String toString() => '${spec.shortName}: no $side shot ($reason)';
}

final class OrbitCompareBatch {
  const OrbitCompareBatch({required this.jobs, required this.missing});

  final List<OrbitCompareJob> jobs;
  final List<OrbitCompareMissing> missing;
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

String _join(String dir, String name) =>
    dir.endsWith('/') ? '$dir$name' : '$dir/$name';

String _writePng(
  String outDir,
  String kind,
  String fileName,
  OrbitImage image,
) {
  final file = File(_join(_join(outDir, kind), fileName));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(encodeOrbitPng(image));
  return _relative(file.path, outDir);
}

/// The path of [path] as seen from inside [base], with forward slashes, so
/// the compare page can open it from beside `results.json`: `diff/x.png`
/// inside the folder, `../shots/x.png` next to it.
///
/// Only a path on another drive stays absolute, because no relative path
/// reaches it.
String _relative(String path, String base) {
  List<String> parts(String p) => File(p).absolute.path
      .replaceAll(r'\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .toList();
  final to = parts(path);
  final from = parts(base);
  if (to.isEmpty ||
      from.isEmpty ||
      to.first.toLowerCase() != from.first.toLowerCase()) {
    return path.replaceAll(r'\', '/');
  }
  var same = 0;
  while (same < to.length &&
      same < from.length &&
      to[same].toLowerCase() == from[same].toLowerCase()) {
    same++;
  }
  return [
    for (var i = same; i < from.length; i++) '..',
    ...to.sublist(same),
  ].join('/');
}
