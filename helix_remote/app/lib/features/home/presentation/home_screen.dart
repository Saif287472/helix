import 'package:flutter/material.dart';

import 'package:helix_remote/shared/widgets/orbit_home_connector.dart';

/// Home on the Orbit screens. A thin connector over [OrbitHomeConnector],
/// which watches the app's providers and builds `orbit_ui`'s `HomeScreen`.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const OrbitHomeConnector();
}
