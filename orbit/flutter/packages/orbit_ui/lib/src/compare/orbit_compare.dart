/// The Flutter half of the screenshot-compare tool.
///
/// `orbit/prototype` is the specification and `orbit/flutter/tools/compare/
/// shoot_html.py` photographs it; this library photographs the ported Flutter
/// screens and measures the two against each other. It exists because of the
/// failure recorded in `PORT_PLAN.md`: "Looks roughly right" passed the last
/// port because nobody could put the two side by side.
///
/// Four pieces:
///
/// - [orbit_devices] - the device sizes and file names both halves agree on.
/// - [orbit_png] - a PNG reader and writer, so the tool has no image-library
///   dependency and cannot silently resize anything.
/// - [orbit_diff] - the comparison and the score.
/// - [orbit_artefacts] - the heat map, the overlay and the flattening.
/// - [orbit_report] - pairing the two manifests, writing `results.json`.
/// - [orbit_fonts] and [orbit_shot] - the render, which needs the real fonts or
///   the comparison is meaningless.
///
/// The score is the plain percentage of pixels that are not byte-identical.
/// **A non-zero score is normal**: Chrome and Flutter rasterise text
/// differently. The score flags a screen for a person's eye; it is not a pass
/// mark, and the compare page sorts worst first.
library;

export 'orbit_artefacts.dart'
    show flattenOrbitImage, orbitBackdrop, orbitDiffHeatMap, orbitOverlay;
export 'orbit_devices.dart'
    show OrbitDevice, OrbitShotSpec, orbitParseShotFileName, orbitShotFileName;
export 'orbit_diff.dart'
    show
        OrbitCompareException,
        OrbitImageDiff,
        compareOrbitImages,
        compareOrbitPngFiles,
        readOrbitPngFile;
export 'orbit_fonts.dart'
    show
        OrbitFontException,
        loadOrbitBundledFonts,
        orbitBundledFonts,
        orbitFamilyIsReallyLoaded;
export 'orbit_png.dart'
    show OrbitImage, OrbitPngException, decodeOrbitPng, encodeOrbitPng;
export 'orbit_report.dart'
    show
        OrbitCompareBatch,
        OrbitCompareJob,
        OrbitCompareMissing,
        OrbitCompareResult,
        OrbitCompareStatus,
        OrbitManifestShot,
        OrbitShotManifest,
        buildOrbitManifest,
        compareOrbitJob,
        compareOrbitJobs,
        orbitCompareJsonFormat,
        orbitScoreMeaning,
        planOrbitBatch,
        sortWorstFirst,
        writeOrbitResultsJson;
export 'orbit_shot.dart'
    show
        OrbitShotBoundary,
        OrbitShotException,
        OrbitShotFile,
        captureOrbitShot,
        orbitShotApp,
        writeOrbitShot;
