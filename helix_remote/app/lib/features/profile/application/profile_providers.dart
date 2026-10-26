import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/engine/failure_copy.dart';
import 'package:helix_remote/core/platform/profile_image_source.dart';
import 'package:helix_remote/features/profile/application/profile_gateway.dart';
import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

/// This account's profile, live.
final profileProvider = StreamProvider<ProfileData>(
  (ref) => ref.watch(profileGatewayProvider).watch(),
);

/// The picture chosen on this phone (see [ProfileAvatarNotifier]).
final profileAvatarBytesProvider = Provider<AsyncValue<Uint8List?>>(
  (ref) => ref.watch(profileAvatarProvider),
);

/// Whether this platform can pick a picture.
final canPickAvatarProvider = Provider<bool>(
  (ref) => ref.watch(profileImageSourceProvider).canPick,
);

abstract final class ProfileRules {
  static const maxName = 50;
  static const maxAbout = 139;

  /// The server's pattern for `~name`: 3 to 32 characters, lower case letters,
  /// digits, `_` and `.`, starting with a letter.
  static final RegExp helixName = RegExp(r'^[a-z][a-z0-9_.]{2,31}$');

  /// `~Anna.K` -> `anna.k`: what the server stores.
  static String normaliseHelixName(String input) =>
      input.trim().replaceFirst(RegExp(r'^~+'), '').toLowerCase();

  /// A sentence about what is wrong with [name], or null when it is fine.
  static String? nameProblem(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter the name people should see.';
    if (trimmed.length > maxName) {
      return 'Keep your name to $maxName characters or fewer.';
    }
    return null;
  }

  static String? aboutProblem(String about) => about.trim().length > maxAbout
      ? 'Keep it to $maxAbout characters or fewer.'
      : null;

  static String? helixNameProblem(String input) {
    final name = normaliseHelixName(input);
    if (name.isEmpty) return 'Enter a name, such as anna.k';
    if (name.length < 3) return 'Names are at least 3 characters.';
    if (name.length > 32) return 'Names are at most 32 characters.';
    if (!RegExp(r'^[a-z]').hasMatch(name)) {
      return 'Names start with a letter.';
    }
    if (!helixName.hasMatch(name)) {
      return 'Use only letters, numbers, dots and underscores.';
    }
    return null;
  }
}

/// What the server said when it refused a `~name`.
///
/// "Taken" and "could be mistaken for Orbit staff" come back as the same
/// answer on purpose (so nobody can probe which staff names exist), so the
/// sentence covers both.
const helixNameUnavailable =
    'That name is not available. It may already be taken, or it may be one '
    'that could be mistaken for Orbit staff, such as a name with admin, '
    'support, official or helix in it. Try another.';

class ProfileEditState {
  const ProfileEditState({
    this.busy = false,
    this.error,
    this.notice,
    this.nameError,
    this.aboutError,
    this.helixNameError,
  });

  final bool busy;

  /// A failure that is not about one field (offline, rate limited).
  final String? error;

  /// "Saved."
  final String? notice;
  final String? nameError;
  final String? aboutError;
  final String? helixNameError;
}

final profileEditProvider =
    NotifierProvider.autoDispose<ProfileEditor, ProfileEditState>(
      ProfileEditor.new,
    );

final class ProfileEditor extends Notifier<ProfileEditState> {
  @override
  ProfileEditState build() => const ProfileEditState();

  ProfileGateway get _gateway => ref.read(profileGatewayProvider);

  /// Saves the name and the about line together: they are one encrypted
  /// profile, so they are published together.
  Future<void> save({required String name, required String about}) async {
    final nameError = ProfileRules.nameProblem(name);
    final aboutError = ProfileRules.aboutProblem(about);
    if (nameError != null || aboutError != null) {
      state = ProfileEditState(nameError: nameError, aboutError: aboutError);
      return;
    }
    state = const ProfileEditState(busy: true);
    try {
      await _gateway.saveProfile(name: name.trim(), about: about.trim());
      state = const ProfileEditState(notice: 'Saved.');
    } on Object catch (error) {
      state = ProfileEditState(error: _failure(error));
    }
  }

  /// Edit profile's one Save: the name and about line, then the `~name` when
  /// it changed ([current] is the one held now; an empty field keeps it, as
  /// only "Remove my ~name" removes it). True when all of it was saved;
  /// otherwise [state] says what was not (a field's error, or `error`).
  Future<bool> saveAll({
    required String name,
    required String about,
    required String helixName,
    String? current,
  }) async {
    await save(name: name, about: about);
    final saved = state;
    if (saved.nameError != null ||
        saved.aboutError != null ||
        saved.error != null) {
      return false;
    }
    final wanted = ProfileRules.normaliseHelixName(helixName);
    if (wanted.isEmpty || wanted == current) return true;
    await saveHelixName(wanted);
    return state.helixNameError == null && state.error == null;
  }

  Future<void> saveHelixName(String input) async {
    final problem = ProfileRules.helixNameProblem(input);
    if (problem != null) {
      state = ProfileEditState(helixNameError: problem);
      return;
    }
    state = const ProfileEditState(busy: true);
    try {
      await _gateway.setHelixName(ProfileRules.normaliseHelixName(input));
      state = const ProfileEditState(notice: 'Your ~name is saved.');
    } on ApiException catch (e) {
      state = switch (e.code) {
        ErrorCode.nameTaken || ErrorCode.invalidField => ProfileEditState(
          helixNameError: e.code == ErrorCode.invalidField
              ? 'Use only letters, numbers, dots and underscores.'
              : helixNameUnavailable,
        ),
        _ => ProfileEditState(error: _failure(e)),
      };
    } on Object catch (error) {
      state = ProfileEditState(error: _failure(error));
    }
  }

  Future<void> clearHelixName() async {
    state = const ProfileEditState(busy: true);
    try {
      await _gateway.clearHelixName();
      state = const ProfileEditState(notice: 'Your ~name is removed.');
    } on Object catch (error) {
      state = ProfileEditState(error: _failure(error));
    }
  }

  /// Lets the person choose a picture, crops it to a square, keeps it on this
  /// phone and shares it with the people this account messages.
  Future<void> chooseAvatar() async {
    state = const ProfileEditState(busy: true);
    try {
      final png = await ref.read(profileImageSourceProvider).pickSquare();
      if (png != null) {
        await ref.read(profileAvatarProvider.notifier).set(png);
        await _publishPhoto(png);
      } else {
        state = const ProfileEditState();
      }
    } on ProfileImageException {
      state = const ProfileEditState(
        error: 'That file could not be read as a picture. Try another.',
      );
    } on Object {
      state = const ProfileEditState(
        error: 'The photo could not be changed. Try again.',
      );
    }
  }

  Future<void> removeAvatar() async {
    await ref.read(profileAvatarProvider.notifier).remove();
    await _publishPhotoRemoved();
  }

  /// Shares the picture kept on this phone. The profile is one encrypted
  /// object, so the name and about line already saved go with it.
  ///
  /// A failure leaves the picture on this phone and says so: the person can
  /// try again.
  Future<void> _publishPhoto(List<int> png) async {
    try {
      final profile = await ref.read(profileProvider.future);
      await _gateway.saveProfile(
        name: profile.name,
        about: profile.about,
        photoBytes: png,
      );
      state = const ProfileEditState(notice: 'Photo updated.');
    } on Object {
      state = const ProfileEditState(
        error:
            'Your photo is on this phone, but it could not be shared. '
            'Try again when you have network.',
      );
    }
  }

  /// Takes the shared picture away as well as the one on this phone.
  Future<void> _publishPhotoRemoved() async {
    try {
      final profile = await ref.read(profileProvider.future);
      await _gateway.saveProfile(
        name: profile.name,
        about: profile.about,
        clearPhoto: true,
      );
      state = const ProfileEditState(notice: 'Photo removed.');
    } on Object {
      state = const ProfileEditState(
        error:
            'The photo is gone from this phone, but the shared one could '
            'not be removed. Try again when you have network.',
      );
    }
  }

  String _failure(Object error) =>
      describeFailure(error, now: ref.read(clockProvider)()).message;
}
