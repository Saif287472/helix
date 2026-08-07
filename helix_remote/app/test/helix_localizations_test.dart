import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

void main() {
  test('application chrome supports English and Bengali', () async {
    final en = await HelixLocalizations.delegate.load(const Locale('en'));
    final bn = await HelixLocalizations.delegate.load(const Locale('bn'));

    expect(en.appTitle, equals('Helix Remote'));
    expect(bn.appTitle, equals('হেলিক্স রিমোট'));
  });
}
