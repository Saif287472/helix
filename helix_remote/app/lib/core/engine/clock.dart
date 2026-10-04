import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The time, behind a provider so a test can fix it. A widget never reads a
/// clock: dates reach it as sentences ("5 minutes ago") built in the
/// application layer from this.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
