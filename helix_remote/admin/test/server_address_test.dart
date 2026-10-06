import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/api/server_address.dart';

void main() {
  String parse(String raw) => ServerAddress.parse(raw).text;
  Matcher refuses(String message) => throwsA(
    isA<ServerAddressException>().having((e) => e.message, 'message', message),
  );

  test('a bare host means https', () {
    expect(parse('helix.example.com'), 'https://helix.example.com');
  });

  test('keeps the port and a path prefix, drops trailing slashes', () {
    expect(
      parse('https://helix.example.com:8443/'),
      'https://helix.example.com:8443',
    );
    expect(
      parse('helix.example.com/admin-api//'),
      'https://helix.example.com/admin-api',
    );
  });

  test('drops a query and a fragment', () {
    expect(
      parse('https://helix.example.com/?a=1#frag'),
      'https://helix.example.com',
    );
  });

  test('trims whitespace', () {
    expect(parse('  helix.example.com \n'), 'https://helix.example.com');
  });

  test('refuses an empty address', () {
    expect(() => parse('   '), refuses('Enter the server address.'));
  });

  test('refuses other schemes', () {
    expect(
      () => parse('ftp://helix.example.com'),
      refuses('The address must start with https://.'),
    );
  });

  test('refuses credentials in the address', () {
    expect(
      () => parse('https://admin:secret@helix.example.com'),
      refuses('Leave the user name and password out of the address.'),
    );
  });

  test('refuses plain http to another machine', () {
    expect(
      () => parse('http://helix.example.com'),
      throwsA(isA<ServerAddressException>()),
    );
    expect(
      () => parse('http://192.168.1.20:8080'),
      throwsA(isA<ServerAddressException>()),
    );
  });

  test('allows plain http on this machine (development)', () {
    expect(parse('http://localhost:8080'), 'http://localhost:8080');
    expect(parse('http://127.0.0.1:8080'), 'http://127.0.0.1:8080');
    expect(parse('http://10.0.2.2:8080'), 'http://10.0.2.2:8080');
    expect(parse('http://helix.localhost'), 'http://helix.localhost');
  });

  test('two spellings of one server are equal', () {
    expect(
      ServerAddress.parse('helix.example.com'),
      ServerAddress.parse('https://helix.example.com/'),
    );
  });
}
