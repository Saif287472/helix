import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/create_group.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// The member picker of New group and Add members over the app's people:
/// everyone who may be added, by name and with their pictures, and the
/// look-up of a number or `~name` this device does not know yet.
orbit.MemberPickerModel memberPickerModel(
  WidgetRef ref, {
  required List<String> selected,
  Set<String> exclude = const {},
}) {
  final candidates = ref.watch(groupCandidateItemsProvider);
  return orbit.MemberPickerModel(
    candidates: candidates.value ?? const [],
    selected: selected,
    exclude: exclude,
    loading: candidates.isLoading && !candidates.hasValue,
    loadFailed: candidates.hasError && !candidates.hasValue,
  );
}

orbit.MemberPickerActions memberPickerActions(
  WidgetRef ref, {
  required void Function(String account) onToggle,
}) => orbit.MemberPickerActions(
  onToggle: onToggle,
  onLookup: (query) async {
    final result = await ref.read(candidateLookupProvider).find(query);
    final found = result.found;
    return (
      found: found == null
          ? null
          : orbit.HelixPersonItem(id: found.account, names: found.names),
      error: result.error,
    );
  },
  onRetry: () => ref.invalidate(groupCandidatesProvider),
);
