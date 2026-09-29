import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/password_vault.dart';

void main() {
  const params = PasswordKdfParams();
  final salt = PasswordVault.newSalt();

  test('the same password and salt always give the same keys', () async {
    final a = await PasswordVault.deriveKeys(
      password: 'correct horse',
      salt: salt,
      params: params,
    );
    final b = await PasswordVault.deriveKeys(
      password: 'correct horse',
      salt: salt,
      params: params,
    );
    expect(a.authKey, b.authKey);
    expect(a.wrapKey, b.wrapKey);
    // The key sent to the server is not the key that unlocks the identity.
    expect(base64Url.decode(base64Url.normalize(a.authKey)), isNot(a.wrapKey));
  });

  test('a different password or salt gives a different auth key', () async {
    final base = await PasswordVault.deriveKeys(
      password: 'correct horse',
      salt: salt,
      params: params,
    );
    final otherPassword = await PasswordVault.deriveKeys(
      password: 'correct horsf',
      salt: salt,
      params: params,
    );
    final otherSalt = await PasswordVault.deriveKeys(
      password: 'correct horse',
      salt: PasswordVault.newSalt(),
      params: params,
    );
    expect(otherPassword.authKey, isNot(base.authKey));
    expect(otherSalt.authKey, isNot(base.authKey));
  });

  test('the identity key round-trips and refuses the wrong key', () async {
    final keys = await PasswordVault.deriveKeys(
      password: 'correct horse',
      salt: salt,
      params: params,
    );
    final identity = List<int>.generate(32, (i) => i);
    final wrapped = await PasswordVault.wrapIdentityKey(
      wrapKey: keys.wrapKey,
      identityPrivateKey: identity,
      identityPublicKey: 'identity-pub',
    );
    expect(
      await PasswordVault.unwrapIdentityKey(
        wrapKey: keys.wrapKey,
        wrapped: wrapped,
        identityPublicKey: 'identity-pub',
      ),
      identity,
    );

    final wrong = await PasswordVault.deriveKeys(
      password: 'wrong horse',
      salt: salt,
      params: params,
    );
    await expectLater(
      PasswordVault.unwrapIdentityKey(
        wrapKey: wrong.wrapKey,
        wrapped: wrapped,
        identityPublicKey: 'identity-pub',
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    // Bound to the identity it wraps.
    await expectLater(
      PasswordVault.unwrapIdentityKey(
        wrapKey: keys.wrapKey,
        wrapped: wrapped,
        identityPublicKey: 'someone-else',
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('short passwords are refused', () {
    expect(PasswordVault.passwordError('short'), isNotNull);
    expect(PasswordVault.passwordError('long enough'), isNull);
  });
}
