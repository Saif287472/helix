/// The Orbit icon set, generated from the prototype's Phosphor names.
///
/// **The prototype is the specification.** Every entry here exists because
/// `orbit/prototype` draws it: the name is the Phosphor class the prototype
/// uses (`ph-<name>`, or `ph-fill` with the name, in `prototype/js` and
/// `prototype/index.html`) and the weight is the one that call site asks for.
/// Nothing was added for looks, and nothing was guessed - each symbol below
/// was read out of `phosphor_flutter` 2.1.0's generated sources
/// (`lib/src/phosphor_icons_<weight>.dart`), not transliterated. Those code
/// points are kept: the icons are declared as plain `IconData` against the
/// bundled Phosphor fonts, because that package's `PhosphorIconData` extends
/// `IconData`, which is `final` in Flutter 3.44 and no longer compiles. See the
/// fonts section of this package's `pubspec.yaml`.
///
/// The prototype asks for a weight per call site; a theme may change the
/// default (`prototype/js/themes.js` sets light, duotone or bold). So each icon
/// is exposed at every weight the prototype uses for it: [OrbitIcons.check] is
/// the regular weight, [OrbitIcons.checkBold] and [OrbitIcons.checkFill] are
/// the others.
///
/// **If an icon in the prototype has no Dart equivalent, do not swap it for a
/// look-alike.** Record it in `orbit/DEVIATIONS.md` and ask, then add it here
/// once it is decided. `README.md` in this directory is the full table,
/// including any name that had to be mapped by hand.
library;

import 'package:flutter/widgets.dart' show IconData;

/// Every Phosphor icon the Orbit prototype draws, by prototype name.
abstract final class OrbitIcons {
  /// `address-book`.
  static const IconData addressBook =
      IconData(
        0xE6F8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `address-book` at fill.
  static const IconData addressBookFill =
      IconData(
        0xE6F8,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `app-window`.
  static const IconData appWindow =
      IconData(
        0xE5DA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `app-window` at fill.
  static const IconData appWindowFill =
      IconData(
        0xE5DA,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `archive`.
  static const IconData archive =
      IconData(
        0xE00C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `archive` at fill.
  static const IconData archiveFill =
      IconData(
        0xE00C,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-bend-up-left`.
  static const IconData arrowBendUpLeft =
      IconData(
        0xE024,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-bend-up-left` at bold.
  static const IconData arrowBendUpLeftBold =
      IconData(
        0xE024,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-bend-up-right`.
  static const IconData arrowBendUpRight =
      IconData(
        0xE026,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-bend-up-right` at bold.
  static const IconData arrowBendUpRightBold =
      IconData(
        0xE026,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-circle-up`.
  static const IconData arrowCircleUp =
      IconData(
        0xE030,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-clockwise`.
  static const IconData arrowClockwise =
      IconData(
        0xE036,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-clockwise` at bold.
  static const IconData arrowClockwiseBold =
      IconData(
        0xE036,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-counter-clockwise`.
  static const IconData arrowCounterClockwise =
      IconData(
        0xE038,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-counter-clockwise` at bold.
  static const IconData arrowCounterClockwiseBold =
      IconData(
        0xE038,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-down-left`.
  static const IconData arrowDownLeft =
      IconData(
        0xE040,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-down-left` at bold.
  static const IconData arrowDownLeftBold =
      IconData(
        0xE040,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-left`.
  static const IconData arrowLeft =
      IconData(
        0xE058,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-square-out`.
  static const IconData arrowSquareOut =
      IconData(
        0xE5DE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-up-right`.
  static const IconData arrowUpRight =
      IconData(
        0xE092,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrow-up-right` at bold.
  static const IconData arrowUpRightBold =
      IconData(
        0xE092,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `arrows-clockwise`.
  static const IconData arrowsClockwise =
      IconData(
        0xE094,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `at`.
  static const IconData at =
      IconData(
        0xE0AC,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `at` at bold.
  static const IconData atBold =
      IconData(
        0xE0AC,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `backspace`.
  static const IconData backspace =
      IconData(
        0xE0AE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `battery-high`.
  static const IconData batteryHigh =
      IconData(
        0xE0C2,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `battery-high` at fill.
  static const IconData batteryHighFill =
      IconData(
        0xE0C2,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `bell`.
  static const IconData bell =
      IconData(
        0xE0CE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `bell-ringing`.
  static const IconData bellRinging =
      IconData(
        0xE5E8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `bell-ringing` at fill.
  static const IconData bellRingingFill =
      IconData(
        0xE5E8,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `bell-slash`.
  static const IconData bellSlash =
      IconData(
        0xE0D4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `bluetooth`.
  static const IconData bluetooth =
      IconData(
        0xE0DA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `bluetooth` at fill.
  static const IconData bluetoothFill =
      IconData(
        0xE0DA,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `book-open-text`.
  static const IconData bookOpenText =
      IconData(
        0xE8F2,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `bug`.
  static const IconData bug =
      IconData(
        0xE5F4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `calendar-blank`.
  static const IconData calendarBlank =
      IconData(
        0xE10A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `camera`.
  static const IconData camera =
      IconData(
        0xE10E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `camera` at fill.
  static const IconData cameraFill =
      IconData(
        0xE10E,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `camera-plus`.
  static const IconData cameraPlus =
      IconData(
        0xEC58,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `camera-plus` at fill.
  static const IconData cameraPlusFill =
      IconData(
        0xEC58,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `camera-rotate`.
  static const IconData cameraRotate =
      IconData(
        0xE7A4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `camera-rotate` at fill.
  static const IconData cameraRotateFill =
      IconData(
        0xE7A4,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `camera-slash`.
  static const IconData cameraSlash =
      IconData(
        0xE110,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `caret-down`.
  static const IconData caretDown =
      IconData(
        0xE136,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `caret-down` at bold.
  static const IconData caretDownBold =
      IconData(
        0xE136,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `caret-left`.
  static const IconData caretLeft =
      IconData(
        0xE138,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `caret-left` at bold.
  static const IconData caretLeftBold =
      IconData(
        0xE138,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `caret-right`.
  static const IconData caretRight =
      IconData(
        0xE13A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `caret-up`.
  static const IconData caretUp =
      IconData(
        0xE13C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `caret-up` at bold.
  static const IconData caretUpBold =
      IconData(
        0xE13C,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cell-signal-full`.
  static const IconData cellSignalFull =
      IconData(
        0xE142,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cell-signal-full` at fill.
  static const IconData cellSignalFullFill =
      IconData(
        0xE142,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cell-signal-low`.
  static const IconData cellSignalLow =
      IconData(
        0xE146,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cell-signal-low` at fill.
  static const IconData cellSignalLowFill =
      IconData(
        0xE146,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chart-bar-horizontal`.
  static const IconData chartBarHorizontal =
      IconData(
        0xE152,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-centered-text`.
  static const IconData chatCenteredText =
      IconData(
        0xE166,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-centered-text` at fill.
  static const IconData chatCenteredTextFill =
      IconData(
        0xE166,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-circle`.
  static const IconData chatCircle =
      IconData(
        0xE168,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-circle` at fill.
  static const IconData chatCircleFill =
      IconData(
        0xE168,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-circle-dots`.
  static const IconData chatCircleDots =
      IconData(
        0xE16C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-circle-dots` at bold.
  static const IconData chatCircleDotsBold =
      IconData(
        0xE16C,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-circle-slash`.
  static const IconData chatCircleSlash =
      IconData(
        0xE16A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chat-dots`.
  static const IconData chatDots =
      IconData(
        0xE170,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chats`.
  static const IconData chats =
      IconData(
        0xE17C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `chats-circle`.
  static const IconData chatsCircle =
      IconData(
        0xE17E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `check`.
  static const IconData check =
      IconData(
        0xE182,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `check` at bold.
  static const IconData checkBold =
      IconData(
        0xE182,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `check-circle`.
  static const IconData checkCircle =
      IconData(
        0xE184,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `check-circle` at fill.
  static const IconData checkCircleFill =
      IconData(
        0xE184,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `checks`.
  static const IconData checks =
      IconData(
        0xE53A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `checks` at fill.
  static const IconData checksFill =
      IconData(
        0xE53A,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `checks` at bold.
  static const IconData checksBold =
      IconData(
        0xE53A,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `circle`.
  static const IconData circle =
      IconData(
        0xE18A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `clipboard-text`.
  static const IconData clipboardText =
      IconData(
        0xE198,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `clock`.
  static const IconData clock =
      IconData(
        0xE19A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `clock-counter-clockwise`.
  static const IconData clockCounterClockwise =
      IconData(
        0xE1A0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cloud-arrow-down`.
  static const IconData cloudArrowDown =
      IconData(
        0xE1AC,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cloud-arrow-up`.
  static const IconData cloudArrowUp =
      IconData(
        0xE1AE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cloud-check`.
  static const IconData cloudCheck =
      IconData(
        0xE1B0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cloud-slash`.
  static const IconData cloudSlash =
      IconData(
        0xE1B6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `cloud-x`.
  static const IconData cloudX =
      IconData(
        0xEA96,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `code`.
  static const IconData code =
      IconData(
        0xE1BC,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `copy`.
  static const IconData copy =
      IconData(
        0xE1CA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `crown-simple`.
  static const IconData crownSimple =
      IconData(
        0xE616,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `database`.
  static const IconData database =
      IconData(
        0xE1DE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `desktop`.
  static const IconData desktop =
      IconData(
        0xE560,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `desktop` at fill.
  static const IconData desktopFill =
      IconData(
        0xE560,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `device-mobile`.
  static const IconData deviceMobile =
      IconData(
        0xE1E0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `device-mobile` at fill.
  static const IconData deviceMobileFill =
      IconData(
        0xE1E0,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `devices`.
  static const IconData devices =
      IconData(
        0xEBA4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `devices` at fill.
  static const IconData devicesFill =
      IconData(
        0xEBA4,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `dots-nine`.
  static const IconData dotsNine =
      IconData(
        0xE1FC,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `dots-nine` at bold.
  static const IconData dotsNineBold =
      IconData(
        0xE1FC,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `dots-three-vertical`.
  static const IconData dotsThreeVertical =
      IconData(
        0xE208,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `download-simple`.
  static const IconData downloadSimple =
      IconData(
        0xE20C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `download-simple` at fill.
  static const IconData downloadSimpleFill =
      IconData(
        0xE20C,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `download-simple` at bold.
  static const IconData downloadSimpleBold =
      IconData(
        0xE20C,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `ear`.
  static const IconData ear =
      IconData(
        0xE70C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `ear` at fill.
  static const IconData earFill =
      IconData(
        0xE70C,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `eraser`.
  static const IconData eraser =
      IconData(
        0xE21E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `export`.
  static const IconData export =
      IconData(
        0xEAF0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `eye`.
  static const IconData eye =
      IconData(
        0xE220,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `eye-slash`.
  static const IconData eyeSlash =
      IconData(
        0xE224,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `file-pdf`.
  static const IconData filePdf =
      IconData(
        0xE702,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `file-text`.
  static const IconData fileText =
      IconData(
        0xE23A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `file-text` at fill.
  static const IconData fileTextFill =
      IconData(
        0xE23A,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `fingerprint`.
  static const IconData fingerprint =
      IconData(
        0xE23E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `flag`.
  static const IconData flag =
      IconData(
        0xE244,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `gear-six`.
  static const IconData gearSix =
      IconData(
        0xE272,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `gif`.
  static const IconData gif =
      IconData(
        0xE274,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `globe-simple`.
  static const IconData globeSimple =
      IconData(
        0xE28E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `hand-pointing`.
  static const IconData handPointing =
      IconData(
        0xE29A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `hard-drives`.
  static const IconData hardDrives =
      IconData(
        0xE2A0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `hard-drives` at fill.
  static const IconData hardDrivesFill =
      IconData(
        0xE2A0,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `headphones`.
  static const IconData headphones =
      IconData(
        0xE2A6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `headphones` at fill.
  static const IconData headphonesFill =
      IconData(
        0xE2A6,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `hourglass-medium`.
  static const IconData hourglassMedium =
      IconData(
        0xE2B8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `hourglass-medium` at fill.
  static const IconData hourglassMediumFill =
      IconData(
        0xE2B8,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `identification-card`.
  static const IconData identificationCard =
      IconData(
        0xE2C8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `image`.
  static const IconData image =
      IconData(
        0xE2CA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `images`.
  static const IconData images =
      IconData(
        0xE836,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `images` at fill.
  static const IconData imagesFill =
      IconData(
        0xE836,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `info`.
  static const IconData info =
      IconData(
        0xE2CE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `key`.
  static const IconData key =
      IconData(
        0xE2D6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `key` at fill.
  static const IconData keyFill =
      IconData(
        0xE2D6,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `keyboard`.
  static const IconData keyboard =
      IconData(
        0xE2D8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `lightning`.
  static const IconData lightning =
      IconData(
        0xE2DE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `lightning` at fill.
  static const IconData lightningFill =
      IconData(
        0xE2DE,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `link-break`.
  static const IconData linkBreak =
      IconData(
        0xE2E4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `link-break` at fill.
  static const IconData linkBreakFill =
      IconData(
        0xE2E4,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `link-simple`.
  static const IconData linkSimple =
      IconData(
        0xE2E6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `link-simple-horizontal`.
  static const IconData linkSimpleHorizontal =
      IconData(
        0xE2EA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `list`.
  static const IconData list =
      IconData(
        0xE2F0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `lock-key`.
  static const IconData lockKey =
      IconData(
        0xE2FE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `lock-key` at fill.
  static const IconData lockKeyFill =
      IconData(
        0xE2FE,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `lock-simple`.
  static const IconData lockSimple =
      IconData(
        0xE308,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `lock-simple` at fill.
  static const IconData lockSimpleFill =
      IconData(
        0xE308,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `lock-simple-open`.
  static const IconData lockSimpleOpen =
      IconData(
        0xE30A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `magnifying-glass`.
  static const IconData magnifyingGlass =
      IconData(
        0xE30C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `magnifying-glass` at bold.
  static const IconData magnifyingGlassBold =
      IconData(
        0xE30C,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `magnifying-glass-minus`.
  static const IconData magnifyingGlassMinus =
      IconData(
        0xE30E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `map-pin`.
  static const IconData mapPin =
      IconData(
        0xE316,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `map-pin` at fill.
  static const IconData mapPinFill =
      IconData(
        0xE316,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `microphone`.
  static const IconData microphone =
      IconData(
        0xE326,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `microphone` at fill.
  static const IconData microphoneFill =
      IconData(
        0xE326,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `microphone-slash`.
  static const IconData microphoneSlash =
      IconData(
        0xE328,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `microphone-slash` at fill.
  static const IconData microphoneSlashFill =
      IconData(
        0xE328,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `minus`.
  static const IconData minus =
      IconData(
        0xE32A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `minus` at light.
  static const IconData minusLight =
      IconData(
        0xE32A,
        fontFamily: 'PhosphorLight',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `monitor`.
  static const IconData monitor =
      IconData(
        0xE32E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `music-note`.
  static const IconData musicNote =
      IconData(
        0xE33C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `number-circle-one`.
  static const IconData numberCircleOne =
      IconData(
        0xE36A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `palette`.
  static const IconData palette =
      IconData(
        0xE6C8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `palette` at fill.
  static const IconData paletteFill =
      IconData(
        0xE6C8,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `paper-plane-tilt`.
  static const IconData paperPlaneTilt =
      IconData(
        0xE398,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `paper-plane-tilt` at fill.
  static const IconData paperPlaneTiltFill =
      IconData(
        0xE398,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `paperclip`.
  static const IconData paperclip =
      IconData(
        0xE39A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `password`.
  static const IconData password =
      IconData(
        0xE752,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `password` at fill.
  static const IconData passwordFill =
      IconData(
        0xE752,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `pause`.
  static const IconData pause =
      IconData(
        0xE39E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `pause` at fill.
  static const IconData pauseFill =
      IconData(
        0xE39E,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `pencil-simple`.
  static const IconData pencilSimple =
      IconData(
        0xE3B4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `pencil-simple` at bold.
  static const IconData pencilSimpleBold =
      IconData(
        0xE3B4,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone`.
  static const IconData phone =
      IconData(
        0xE3B8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone` at fill.
  static const IconData phoneFill =
      IconData(
        0xE3B8,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-call`.
  static const IconData phoneCall =
      IconData(
        0xE3BA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-disconnect`.
  static const IconData phoneDisconnect =
      IconData(
        0xE3BC,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-disconnect` at fill.
  static const IconData phoneDisconnectFill =
      IconData(
        0xE3BC,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-disconnect` at bold.
  static const IconData phoneDisconnectBold =
      IconData(
        0xE3BC,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-incoming`.
  static const IconData phoneIncoming =
      IconData(
        0xE3BE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-incoming` at fill.
  static const IconData phoneIncomingFill =
      IconData(
        0xE3BE,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-plus`.
  static const IconData phonePlus =
      IconData(
        0xEC56,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-plus` at bold.
  static const IconData phonePlusBold =
      IconData(
        0xEC56,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `phone-x`.
  static const IconData phoneX =
      IconData(
        0xE3C4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `play`.
  static const IconData play =
      IconData(
        0xE3D0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `play` at fill.
  static const IconData playFill =
      IconData(
        0xE3D0,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `play-circle`.
  static const IconData playCircle =
      IconData(
        0xE3D2,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `play-circle` at fill.
  static const IconData playCircleFill =
      IconData(
        0xE3D2,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `plus`.
  static const IconData plus =
      IconData(
        0xE3D4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `plus` at bold.
  static const IconData plusBold =
      IconData(
        0xE3D4,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `prohibit`.
  static const IconData prohibit =
      IconData(
        0xE3DE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `prohibit` at fill.
  static const IconData prohibitFill =
      IconData(
        0xE3DE,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `push-pin`.
  static const IconData pushPin =
      IconData(
        0xE3E2,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `push-pin` at fill.
  static const IconData pushPinFill =
      IconData(
        0xE3E2,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `qr-code`.
  static const IconData qrCode =
      IconData(
        0xE3E6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `qr-code` at fill.
  static const IconData qrCodeFill =
      IconData(
        0xE3E6,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `question`.
  static const IconData question =
      IconData(
        0xE3E8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `radio-button`.
  static const IconData radioButton =
      IconData(
        0xEB08,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `scan`.
  static const IconData scan =
      IconData(
        0xEBB6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `scroll`.
  static const IconData scroll =
      IconData(
        0xEB7A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `seal-check`.
  static const IconData sealCheck =
      IconData(
        0xE606,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `seal-check` at fill.
  static const IconData sealCheckFill =
      IconData(
        0xE606,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `share-network`.
  static const IconData shareNetwork =
      IconData(
        0xE408,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `shield`.
  static const IconData shield =
      IconData(
        0xE40A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `shield-check`.
  static const IconData shieldCheck =
      IconData(
        0xE40C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `shield-check` at fill.
  static const IconData shieldCheckFill =
      IconData(
        0xE40C,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `shield-star`.
  static const IconData shieldStar =
      IconData(
        0xEC34,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `shield-warning`.
  static const IconData shieldWarning =
      IconData(
        0xE412,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `shield-warning` at fill.
  static const IconData shieldWarningFill =
      IconData(
        0xE412,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `sign-in`.
  static const IconData signIn =
      IconData(
        0xE428,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `sign-out`.
  static const IconData signOut =
      IconData(
        0xE42A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `siren`.
  static const IconData siren =
      IconData(
        0xE9B8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `sliders-horizontal`.
  static const IconData slidersHorizontal =
      IconData(
        0xE434,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `smiley`.
  static const IconData smiley =
      IconData(
        0xE436,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `speaker-high`.
  static const IconData speakerHigh =
      IconData(
        0xE44A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `speaker-high` at fill.
  static const IconData speakerHighFill =
      IconData(
        0xE44A,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `speaker-slash`.
  static const IconData speakerSlash =
      IconData(
        0xE45A,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `spinner-gap`.
  static const IconData spinnerGap =
      IconData(
        0xE66C,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `spinner-gap` at bold.
  static const IconData spinnerGapBold =
      IconData(
        0xE66C,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `square`.
  static const IconData square =
      IconData(
        0xE45E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `square` at light.
  static const IconData squareLight =
      IconData(
        0xE45E,
        fontFamily: 'PhosphorLight',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `sticker`.
  static const IconData sticker =
      IconData(
        0xE5AC,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `tag`.
  static const IconData tag =
      IconData(
        0xE478,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `timer`.
  static const IconData timer =
      IconData(
        0xE492,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `trash`.
  static const IconData trash =
      IconData(
        0xE4A6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `trash` at fill.
  static const IconData trashFill =
      IconData(
        0xE4A6,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `trash-simple`.
  static const IconData trashSimple =
      IconData(
        0xE4A8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `tray-arrow-up`.
  static const IconData trayArrowUp =
      IconData(
        0xEE52,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `tray-arrow-up` at fill.
  static const IconData trayArrowUpFill =
      IconData(
        0xEE52,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `upload-simple`.
  static const IconData uploadSimple =
      IconData(
        0xE4C0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `upload-simple` at bold.
  static const IconData uploadSimpleBold =
      IconData(
        0xE4C0,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user`.
  static const IconData user =
      IconData(
        0xE4C2,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user-circle`.
  static const IconData userCircle =
      IconData(
        0xE4C4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user-circle-dashed`.
  static const IconData userCircleDashed =
      IconData(
        0xEC36,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user-circle-gear`.
  static const IconData userCircleGear =
      IconData(
        0xE4C6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user-circle-plus`.
  static const IconData userCirclePlus =
      IconData(
        0xE4CA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user-minus`.
  static const IconData userMinus =
      IconData(
        0xE4CE,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user-plus`.
  static const IconData userPlus =
      IconData(
        0xE4D0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `user-plus` at bold.
  static const IconData userPlusBold =
      IconData(
        0xE4D0,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `users-three`.
  static const IconData usersThree =
      IconData(
        0xE68E,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `users-three` at fill.
  static const IconData usersThreeFill =
      IconData(
        0xE68E,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `users-three` at bold.
  static const IconData usersThreeBold =
      IconData(
        0xE68E,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `vibrate`.
  static const IconData vibrate =
      IconData(
        0xE4D8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `video-camera`.
  static const IconData videoCamera =
      IconData(
        0xE4DA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `video-camera` at fill.
  static const IconData videoCameraFill =
      IconData(
        0xE4DA,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `video-camera-slash`.
  static const IconData videoCameraSlash =
      IconData(
        0xE4DC,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `video-camera-slash` at fill.
  static const IconData videoCameraSlashFill =
      IconData(
        0xE4DC,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `warning`.
  static const IconData warning =
      IconData(
        0xE4E0,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `warning` at fill.
  static const IconData warningFill =
      IconData(
        0xE4E0,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `warning-circle`.
  static const IconData warningCircle =
      IconData(
        0xE4E2,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `warning-circle` at fill.
  static const IconData warningCircleFill =
      IconData(
        0xE4E2,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `wifi-high`.
  static const IconData wifiHigh =
      IconData(
        0xE4EA,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `wifi-high` at fill.
  static const IconData wifiHighFill =
      IconData(
        0xE4EA,
        fontFamily: 'PhosphorFill',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `wifi-slash`.
  static const IconData wifiSlash =
      IconData(
        0xE4F2,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `wrench`.
  static const IconData wrench =
      IconData(
        0xE5D4,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `x`.
  static const IconData x =
      IconData(
        0xE4F6,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `x` at bold.
  static const IconData xBold =
      IconData(
        0xE4F6,
        fontFamily: 'PhosphorBold',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `x` at light.
  static const IconData xLight =
      IconData(
        0xE4F6,
        fontFamily: 'PhosphorLight',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );

  /// `x-circle`.
  static const IconData xCircle =
      IconData(
        0xE4F8,
        fontFamily: 'PhosphorRegular',
        fontPackage: 'orbit_ui',
        matchTextDirection: true,
      );
}
