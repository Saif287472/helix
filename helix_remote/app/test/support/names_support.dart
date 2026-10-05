import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A [PeopleDirectory] from the four-name shape the call, group and journey
/// tests state their people in.
///
/// It builds the same [PersonName] the app builds from a people row, so
/// `display`, `source` and the secondary line follow the one naming order.
PeopleDirectory directoryOf(Map<String, HelixPersonNames> people) =>
    PeopleDirectory({
      for (final entry in people.entries)
        entry.key: PersonName(
          accountId: entry.key,
          names: entry.value,
          display: entry.value.display,
          phoneNumber: entry.value.number,
          helixName: entry.value.helixName,
        ),
    });
