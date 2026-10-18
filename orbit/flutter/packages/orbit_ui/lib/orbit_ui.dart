/// The Orbit design system.
///
/// A screen gets a model and an actions object, and nothing else: it never
/// reads a provider, the database, the router or the engine (`AGENTS.md`).
///
/// The theme layer comes first (see `PORT_PLAN.md`, Phase 2): a theme is data,
/// loaded from JSON, and there is no per-theme constant anywhere in this
/// package.
library;

export 'src/brand/orbit_mark.dart';
export 'src/gallery/theme_gallery.dart';
export 'src/icons/orbit_icons.dart';
export 'src/startup/orbit_startup.dart';
export 'src/theme/effects.dart';
export 'src/theme/motion.dart';
export 'src/theme/orbit_font_families.dart';
export 'src/theme/orbit_theme.dart';
export 'src/theme/orbit_tokens.dart';
