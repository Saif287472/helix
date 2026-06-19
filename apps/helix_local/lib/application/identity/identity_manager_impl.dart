import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:convert/convert.dart' as cvt;
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:flutter/services.dart' show rootBundle;

import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/controllers/secret_code_service.dart';
import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';

class IdentityManagerImpl implements IdentityManager {
  final ProfileRepository _profileRepository;
  final SecureIdentityStore _secureIdentityStore;
  // Windows flutter_secure_storage uses a file under the product's appDataFolder.
  // Injected so callers can override without hardcoding the path here.
  final String _appDataFolder;

  Profile? _profile;
  DeviceIdentity? _identity;
  bool _isFirstRun = true;
  List<String>? _wordList;

  final StreamController<Profile> _profileController =
      StreamController<Profile>.broadcast();

  IdentityManagerImpl({
    required this._profileRepository,
    required this._secureIdentityStore,
    this._appDataFolder = 'com.helix/helix',
  });

  @override
  Profile? get profile => _profile;

  @override
  DeviceIdentity? get identity => _identity;

  @override
  bool get isFirstRun => _isFirstRun;

  @override
  Stream<Profile> get profileChanges => _profileController.stream;

  @override
  Future<void> init() async {
    await _loadWordList();

    try {
      await _initFromStorage();
    } catch (e) {
      if (!_isSecureStorageFailure(e)) rethrow;
      await reset();
    }
  }

  Future<void> _initFromStorage() async {
    _isFirstRun = await _secureIdentityStore.isFirstRun();
    _identity = await _secureIdentityStore.loadIdentity();
    _profile = await _profileRepository.loadProfile();
  }

  @override
  Future<void> createProfile(
    String displayName,
    String secretCode,
    DiscoverabilityState disc,
  ) async {
    final nameError = validateDisplayName(displayName);
    if (nameError != null) throw ArgumentError(nameError);

    final codeError = validateSecretCode(secretCode);
    if (codeError != null) throw ArgumentError(codeError);

    final identity = await _generateDeviceIdentity();
    final verifier = await _deriveSecretCodeVerifier(secretCode);

    await _secureIdentityStore.saveIdentity(identity);
    await _secureIdentityStore.saveSecretCode(secretCode);
    await _secureIdentityStore.saveSecretCodeVerifier(verifier);
    await _secureIdentityStore.setFirstRunDone();

    _identity = identity;
    _isFirstRun = false;

    final p = Profile(displayName: displayName, discoverability: disc);
    await _profileRepository.saveProfile(p);

    _profile = p;
    _profileController.add(p);
  }

  @override
  Future<void> updateDisplayName(String name) async {
    final error = validateDisplayName(name);
    if (error != null) throw ArgumentError(error);
    if (_profile == null) return;
    final updated = _profile!.copyWith(displayName: name);
    await _profileRepository.saveProfile(updated);
    _profile = updated;
    _profileController.add(updated);
  }

  @override
  Future<void> updateSecretCode(String code) async {
    final error = validateSecretCode(code);
    if (error != null) throw ArgumentError(error);
    final verifier = await _deriveSecretCodeVerifier(code);
    await _secureIdentityStore.saveSecretCode(code);
    await _secureIdentityStore.saveSecretCodeVerifier(verifier);
    if (_profile != null) _profileController.add(_profile!);
  }

  @override
  Future<String?> getSecretCode() => _secureIdentityStore.loadSecretCode();

  @override
  Future<String?> getSecretCodeVerifier() =>
      _secureIdentityStore.loadSecretCodeVerifier();

  @override
  Future<void> updateDiscoverability(DiscoverabilityState state) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(discoverability: state);
    await _profileRepository.saveProfile(updated);
    _profile = updated;
    _profileController.add(updated);
  }

  @override
  Future<void> updatePreferences({
    bool? notifyShowSender,
    bool? notifySound,
    bool? copyEnabled,
    bool? screenshotProtect,
    String? themeMode,
    String? accentColor,
    bool? amoledDark,
    bool? readReceiptsEnabled,
    bool? typingIndicatorsEnabled,
    bool? homeWelcomeDismissed,
    bool? biometricLock,
    int? lockAfterMinutes,
    String? ringtoneAsset,
  }) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(
      notifyShowSender: notifyShowSender,
      notifySound: notifySound,
      copyEnabled: copyEnabled,
      screenshotProtect: screenshotProtect,
      themeMode: themeMode,
      accentColor: accentColor,
      amoledDark: amoledDark,
      readReceiptsEnabled: readReceiptsEnabled,
      typingIndicatorsEnabled: typingIndicatorsEnabled,
      homeWelcomeDismissed: homeWelcomeDismissed,
      biometricLock: biometricLock,
      lockAfterMinutes: lockAfterMinutes,
      ringtoneAsset: ringtoneAsset,
    );
    await _profileRepository.saveProfile(updated);
    _profile = updated;
    _profileController.add(updated);
  }

  @override
  Future<void> resetPreferencesToDefaults() async {
    if (_profile == null) return;
    final updated = _profile!.resetToDefaultPreferences();
    await _profileRepository.saveProfile(updated);
    _profile = updated;
    _profileController.add(updated);
  }

  @override
  Future<void> reset() async {
    try {
      await _secureIdentityStore.clear();
      await _profileRepository.clear();
    } catch (_) {}
    await _deleteWindowsSecureStorageFile();
    _profile = null;
    _identity = null;
    _isFirstRun = true;
  }

  bool _isSecureStorageFailure(Object error) {
    final message = error.toString();
    return message.contains('CryptUnprotectData') ||
        message.contains('flutter_secure_storage') ||
        message.contains('Failed to decrypt data') ||
        message.contains('PlatformException');
  }

  Future<void> _deleteWindowsSecureStorageFile() async {
    if (!isWindows) return;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;

    // _appDataFolder is the product-scoped relative path (e.g. "com.helix/helix").
    // Using injected value prevents hardcoding the Local product path here.
    final relativeParts = _appDataFolder.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    final file = File(
      '$appData${Platform.pathSeparator}$relativeParts'
      '${Platform.pathSeparator}flutter_secure_storage.dat',
    );
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort repair; a locked file will be retried on the next startup.
    }
  }

  @override
  String generateDicewarePassphrase() {
    if (_wordList == null || _wordList!.isEmpty) {
      throw StateError('Word list not loaded');
    }
    // Diceware-style passphrase: each word is picked with a cryptographically
    // secure, uniformly-distributed index into the EFF large wordlist
    // (assets/eff_large_wordlist.txt, 7776 words) — equivalent to rolling
    // five 6-sided dice per word, since Random.secure().nextInt(max) is
    // bias-free for any max. Words may repeat, matching real diceware.
    final rng = Random.secure();
    final words = <String>[];
    for (var i = 0; i < kDicewareWordCount; i++) {
      words.add(_wordList![rng.nextInt(_wordList!.length)]);
    }
    return words.join(' ');
  }

  @override
  String? validateDisplayName(String s) {
    if (s.length < kDisplayNameMin) {
      return 'Display name must be at least $kDisplayNameMin characters.';
    }
    if (s.length > kDisplayNameMax) {
      return 'Display name must be at most $kDisplayNameMax characters.';
    }
    for (final cp in s.runes) {
      if (cp < 0x20 || cp == 0x7F) {
        return 'Display name must not contain control characters.';
      }
    }
    if (s.runes.toSet().length == 1) {
      return 'Display name must not consist of a single repeated character.';
    }
    return null;
  }

  @override
  String? validateSecretCode(String s) {
    if (s.length < kSecretCodeMin) {
      return 'Secret sentence must be at least $kSecretCodeMin characters.';
    }
    if (s.length > kSecretCodeMax) {
      return 'Secret sentence must be at most $kSecretCodeMax characters.';
    }
    for (final cp in s.runes) {
      if (cp < 0x20 || cp == 0x7F) {
        return 'Secret sentence must not contain control characters.';
      }
    }
    if (s.runes.toSet().length == 1) {
      return 'Secret sentence must not consist of a single repeated character.';
    }
    return null;
  }

  Future<void> _loadWordList() async {
    try {
      final raw = await rootBundle.loadString('assets/eff_large_wordlist.txt');
      _wordList = raw
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map((line) {
            // EFF large wordlist format: "11111\tword"
            final parts = line.split('\t');
            return parts.length >= 2 ? parts[1].trim() : parts[0].trim();
          })
          .where((w) => w.isNotEmpty)
          .toList();
    } catch (_) {
      _wordList = [];
    }
  }

  Future<DeviceIdentity> _generateDeviceIdentity() async {
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;

    final csrPem = X509Utils.generateRsaCsrPem(
      {'CN': 'Helix Device'},
      privateKey,
      publicKey,
    );

    final certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csrPem,
      365 * 5,
    );

    final privateKeyPem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);

    final digest = pkg_crypto.sha256.convert(_modulusBytes(publicKey));
    final fingerprintHex = cvt.hex.encode(digest.bytes);
    final fingerprint = fingerprintHex.substring(0, 32);
    final suffix = fingerprintHex.substring(0, 4);

    return DeviceIdentity(
      certPem: certPem,
      privateKeyPem: privateKeyPem,
      staticPublicKeyFingerprint: fingerprint,
      deviceSuffix: suffix,
    );
  }

  Future<String> _deriveSecretCodeVerifier(String code) async {
    return SecretCodeService.deriveVerifier(code);
  }

  static Uint8List _modulusBytes(RSAPublicKey key) {
    final hex = key.modulus!.toRadixString(16);
    final padded = hex.length.isOdd ? '0$hex' : hex;
    return Uint8List.fromList(
      List.generate(
        padded.length ~/ 2,
        (i) => int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    );
  }

  @override
  void dispose() {
    _profileController.close();
  }
}
