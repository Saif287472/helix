// lib/core/identity_phrase.dart
//
// Derives a short human-readable phrase from two peer fingerprints.
// Sorting before hashing ensures both sides always produce the same phrase
// regardless of which peer is "own" and which is "remote".
import 'dart:convert';

import 'package:crypto/crypto.dart';

// 256 short, phonetically distinct English words — one per byte of SHA-256 output.
const List<String> _kWords = [
  // 0x00–0x0F
  'able', 'acid', 'aged', 'army', 'back', 'ball', 'band', 'bank',
  'base', 'bath', 'bear', 'beat', 'bell', 'best', 'bird', 'blow',
  // 0x10–0x1F
  'blue', 'boat', 'bold', 'bond', 'bone', 'book', 'born', 'bulk',
  'burn', 'busy', 'cage', 'cake', 'call', 'calm', 'camp', 'card',
  // 0x20–0x2F
  'care', 'cart', 'cave', 'cell', 'clay', 'club', 'coal', 'coat',
  'code', 'coil', 'coin', 'cold', 'cook', 'cool', 'cope', 'cord',
  // 0x30–0x3F
  'core', 'corn', 'cost', 'crew', 'crop', 'cube', 'curb', 'cure',
  'cute', 'damp', 'dark', 'data', 'dawn', 'dead', 'deal', 'dear',
  // 0x40–0x4F
  'debt', 'deck', 'deep', 'deer', 'desk', 'diet', 'dire', 'disk',
  'dive', 'dock', 'dome', 'door', 'dose', 'dove', 'drag', 'draw',
  // 0x50–0x5F
  'drip', 'drop', 'drum', 'dual', 'dusk', 'dust', 'duty', 'each',
  'earn', 'edge', 'emit', 'epic', 'exam', 'face', 'fact', 'fail',
  // 0x60–0x6F
  'fair', 'fall', 'fame', 'farm', 'fast', 'fate', 'fawn', 'fear',
  'feel', 'felt', 'fern', 'file', 'fill', 'film', 'find', 'fine',
  // 0x70–0x7F
  'fire', 'firm', 'fish', 'fist', 'flag', 'flat', 'flip', 'flow',
  'flux', 'foam', 'foil', 'fold', 'folk', 'fond', 'food', 'fort',
  // 0x80–0x8F
  'frog', 'fuel', 'gale', 'game', 'gate', 'gaze', 'gear', 'germ',
  'gift', 'glad', 'glow', 'gold', 'good', 'grab', 'gray', 'grid',
  // 0x90–0x9F
  'grip', 'grow', 'gulf', 'gust', 'halt', 'harp', 'hash', 'haze',
  'head', 'heal', 'heap', 'heat', 'helm', 'help', 'hero', 'hide',
  // 0xA0–0xAF
  'high', 'hill', 'hold', 'hole', 'home', 'hook', 'hope', 'horn',
  'host', 'hull', 'hunt', 'husk', 'icon', 'idle', 'inch', 'iris',
  // 0xB0–0xBF
  'jade', 'jolt', 'jump', 'just', 'keen', 'kind', 'king', 'knee',
  'knot', 'lake', 'lamp', 'land', 'lark', 'last', 'lawn', 'lead',
  // 0xC0–0xCF
  'leaf', 'lean', 'left', 'lens', 'lime', 'link', 'lion', 'list',
  'load', 'loan', 'lock', 'loop', 'loss', 'lung', 'mace', 'mark',
  // 0xD0–0xDF
  'mast', 'maze', 'meal', 'melt', 'mesh', 'mild', 'milk', 'mint',
  'mist', 'mode', 'mold', 'mood', 'moor', 'moss', 'moth', 'mule',
  // 0xE0–0xEF
  'myth', 'nail', 'neck', 'nest', 'node', 'norm', 'nose', 'note',
  'oath', 'onto', 'orca', 'oven', 'pace', 'pack', 'pail', 'palm',
  // 0xF0–0xFF
  'part', 'path', 'peak', 'pier', 'pine', 'plan', 'plot', 'pole',
  'pool', 'port', 'post', 'prey', 'pull', 'pure', 'push', 'race',
];

/// Derives a 6-word verification phrase from two 32-char hex fingerprints.
///
/// Both peers produce the same phrase because the inputs are sorted before
/// hashing. Changing either fingerprint changes the phrase completely.
String buildVerificationPhrase(String fp1, String fp2) {
  final a = fp1.toLowerCase();
  final b = fp2.toLowerCase();
  final sorted = a.compareTo(b) <= 0 ? '$a:$b' : '$b:$a';
  final digest = sha256.convert(utf8.encode(sorted));
  final bytes = digest.bytes;
  return List.generate(6, (i) => _kWords[bytes[i]]).join(' ');
}
