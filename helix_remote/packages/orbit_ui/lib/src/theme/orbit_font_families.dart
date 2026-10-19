/// Which font families this build can draw, and the name Flutter knows each
/// one by.
///
/// A family declared in `orbit_ui/pubspec.yaml` belongs to this package, so an
/// app that depends on it has to ask for `packages/orbit_ui/Geist`, not
/// `Geist`. Asking for the bare name draws the platform's font instead, with no
/// error - which is how every Geist line in the preview came out in Segoe UI.
/// [OrbitFontStack.family] goes through here, so no screen spells the prefix.
///
/// Only Orbit's and Orbit Night's families ship in the package (PORT_PLAN.md,
/// Phase 2). The other themes' fonts arrive the way a theme pack's will: the
/// host app has them and says so with [registerPack].
abstract final class OrbitFonts {
  /// The families `orbit_ui` bundles, by the name the theme JSON uses.
  static const bundled = <String>{'Geist', 'Geist Mono'};

  static final Set<String> _packs = <String>{};

  /// Says the host app can draw [families] under their own names, as the
  /// preview does for the six pack themes and a downloaded pack will.
  static void registerPack(Iterable<String> families) =>
      _packs.addAll(families);

  /// The name to hand [TextStyle.fontFamily] for [family], or null when this
  /// build cannot draw it.
  static String? qualify(String family) {
    if (bundled.contains(family)) return 'packages/orbit_ui/$family';
    if (_packs.contains(family)) return family;
    return null;
  }
}
