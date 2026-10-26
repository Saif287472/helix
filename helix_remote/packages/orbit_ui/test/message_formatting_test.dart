import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// `*bold*`, `_italic_`, `~strike~` and `` `mono` `` in a message, read the
/// way WhatsApp reads them.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  const base = TextStyle(fontSize: 15);

  TextSpan read(String text, {List<HelixTextRange> mentions = const []}) =>
      richMessageText(orbit, HelixTextContent(text, mentions: mentions), base);

  /// The (text, style) of every leaf, with its parents' styles merged in.
  List<(String, TextStyle)> leaves(TextSpan span) {
    final out = <(String, TextStyle)>[];
    void walk(InlineSpan s, TextStyle inherited) {
      if (s is! TextSpan) return;
      final style = inherited.merge(s.style);
      if (s.text != null) out.add((s.text!, style));
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c, style);
      }
    }

    walk(span, const TextStyle());
    return out;
  }

  TextStyle styleOf(TextSpan span, String text) =>
      leaves(span).firstWhere((l) => l.$1 == text).$2;

  test('each marker styles its words and is hidden', () {
    final span = read('*bold* _slanted_ ~gone~ `code`');
    expect(span.toPlainText(), 'bold slanted gone code');
    expect(styleOf(span, 'bold').fontWeight, FontWeight.w700);
    expect(styleOf(span, 'slanted').fontStyle, FontStyle.italic);
    expect(styleOf(span, 'gone').decoration, TextDecoration.lineThrough);
    expect(styleOf(span, 'code').fontFamily, orbit.mono.family);
  });

  test('markers nest, and mono is literal', () {
    final span = read('*bold _both_* `*not bold*`');
    expect(span.toPlainText(), 'bold both *not bold*');
    final both = styleOf(span, 'both');
    expect(both.fontWeight, FontWeight.w700);
    expect(both.fontStyle, FontStyle.italic);
    expect(styleOf(span, '*not bold*').fontWeight, isNot(FontWeight.w700));
  });

  test('text that only looks like a marker stays as typed', () {
    for (final plain in [
      'snake_case_name',
      '2*3*4',
      '* a bullet',
      'a * b * c',
      'a lone * star',
      'half _open',
      '__',
    ]) {
      expect(read(plain).toPlainText(), plain, reason: plain);
    }
  });

  test('a link and a mention keep their own look and their text', () {
    const text = '*hi* @sam see https://example.org/a_b_c now';
    final span = read(text, mentions: const [HelixTextRange(5, 4)]);
    expect(span.toPlainText(), 'hi @sam see https://example.org/a_b_c now');
    expect(
      styleOf(span, 'https://example.org/a_b_c').decoration,
      TextDecoration.underline,
    );
    expect(styleOf(span, '@sam').fontWeight, FontWeight.w600);
  });
}
