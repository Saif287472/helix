import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/groups/application/group_errors.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_picture.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';
import 'package:orbit_ui/models.dart' show HelixPersonItem;

/// The longest group name.
const kGroupNameMaxLength = 100;

/// The most people one group holds.
const kGroupMaxMembers = 1024;

/// People who can be put in a group (blocked people left out), live.
final groupCandidatesProvider =
    StreamProvider.autoDispose<List<GroupCandidate>>((ref) async* {
      final port = await ref.watch(groupsPortProvider.future);
      yield* port.watchCandidates().map(
        (all) => [
          for (final c in all)
            if (!c.blocked) c,
        ],
      );
    });

/// The candidates as picker rows: by name, with their pictures.
final groupCandidateItemsProvider =
    Provider.autoDispose<AsyncValue<List<HelixPersonItem>>>((ref) {
      final candidates = ref.watch(groupCandidatesProvider);
      final names =
          ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
      return candidates.whenData(
        (list) =>
            [
              for (final c in list)
                HelixPersonItem(
                  id: c.account,
                  names: c.names,
                  image: names.imageOf(c.account),
                ),
            ]..sort(
              (a, b) => a.names.display.toLowerCase().compareTo(
                b.names.display.toLowerCase(),
              ),
            ),
      );
    });

/// Finds somebody by phone number or `~Helix name`, who this device may not
/// know yet. The engine remembers whoever it finds, so they then appear in
/// [groupCandidatesProvider].
final candidateLookupProvider = Provider<CandidateLookup>(CandidateLookup.new);

final class CandidateLookup {
  CandidateLookup(this._ref);

  final Ref _ref;

  /// The account found, or null with [error] set to what to tell the person.
  Future<({GroupCandidate? found, String? error})> find(String query) async {
    try {
      final port = await _ref.read(groupsPortProvider.future);
      final found = await port.lookup(query);
      if (found == null) {
        return (
          found: null,
          error: 'Nobody on Helix matches that. Check the number or name.',
        );
      }
      if (found.blocked) {
        return (
          found: null,
          error: 'You blocked this person. Unblock them to add them.',
        );
      }
      return (found: found, error: null);
    } on Object catch (error) {
      return (
        found: null,
        error: groupErrorText(error, context: GroupContext.members),
      );
    }
  }
}

/// The new-group form.
@immutable
final class CreateGroupState {
  const CreateGroupState({
    this.name = '',
    this.selected = const [],
    this.picture,
    this.creating = false,
    this.error,
    this.nameError = false,
  });

  final String name;

  /// Accounts chosen, in the order they were chosen.
  final List<String> selected;

  /// The chosen picture, already scaled.
  final Uint8List? picture;
  final bool creating;
  final String? error;

  /// Create was tapped without a usable name.
  final bool nameError;

  /// "Enter a group name of 1 to 100 characters." while [nameError].
  String? get nameErrorText => nameError
      ? 'Enter a group name of 1 to $kGroupNameMaxLength characters.'
      : null;

  bool get nameValid {
    final trimmed = name.trim();
    return trimmed.isNotEmpty && trimmed.length <= kGroupNameMaxLength;
  }

  /// A group needs a name; people can be added later or by link.
  bool get canCreate => nameValid && !creating;

  CreateGroupState copyWith({
    String? name,
    List<String>? selected,
    Uint8List? picture,
    bool clearPicture = false,
    bool? creating,
    String? error,
    bool clearError = false,
    bool? nameError,
  }) => CreateGroupState(
    name: name ?? this.name,
    selected: selected ?? this.selected,
    picture: clearPicture ? null : picture ?? this.picture,
    creating: creating ?? this.creating,
    error: clearError ? null : error ?? this.error,
    nameError: nameError ?? this.nameError,
  );
}

final createGroupProvider =
    NotifierProvider.autoDispose<CreateGroupController, CreateGroupState>(
      CreateGroupController.new,
    );

final class CreateGroupController extends Notifier<CreateGroupState> {
  @override
  CreateGroupState build() => const CreateGroupState();

  void setName(String name) =>
      state = state.copyWith(name: name, clearError: true, nameError: false);

  void toggle(String account) {
    final selected = [...state.selected];
    if (!selected.remove(account)) {
      if (selected.length >= kGroupMaxMembers - 1) {
        state = state.copyWith(
          error: 'A group holds at most $kGroupMaxMembers people.',
        );
        return;
      }
      selected.add(account);
    }
    state = state.copyWith(selected: selected, clearError: true);
  }

  /// Chooses the picture; the sentence to show when the file could not be
  /// used.
  Future<String?> pickPicture() async {
    try {
      final bytes = await ref.read(groupPicturePickerProvider).pick();
      if (bytes != null) state = state.copyWith(picture: bytes);
      return null;
    } on UnusablePicture {
      return UnusablePicture.message;
    }
  }

  void clearPicture() => state = state.copyWith(clearPicture: true);

  /// Creates the group. Returns it, or null with [CreateGroupState.error]
  /// set. People kept out by their privacy settings come back in
  /// [CreatedGroupInfo.rejected]: the group exists, and they need a link.
  Future<CreatedGroupInfo?> create() async {
    if (state.creating) return null;
    if (!state.nameValid) {
      // Create stays tappable; a missing name is said under the field.
      state = state.copyWith(nameError: true);
      return null;
    }
    state = state.copyWith(creating: true, clearError: true);
    try {
      final port = await ref.read(groupsPortProvider.future);
      final created = await port.create(
        name: state.name.trim(),
        members: state.selected,
        picture: state.picture,
      );
      state = state.copyWith(creating: false);
      return created;
    } on Object catch (error) {
      state = state.copyWith(
        creating: false,
        error: groupErrorText(error, context: GroupContext.create),
      );
      return null;
    }
  }
}
