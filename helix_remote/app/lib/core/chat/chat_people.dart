import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show PersonNaming;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Who everyone in the chat screens is, named by the product rule: phone-book
/// name, then nickname, then number, then `~Helix name` (the engine's
/// [PersonNaming]; a profile name and a short id are the fallbacks so a row is
/// never blank).
///
/// This is the chat screens' one adapter onto the people table. It is read
/// through [chatPeopleProvider], so the people feature's own naming helper can
/// replace it by replacing that provider, without touching a screen.
@immutable
class ChatPeople {
  ChatPeople(Iterable<PersonRow> people)
    : _byId = {for (final person in people) person.accountId: person};

  /// Nobody known yet (the first frame, before the table has been read).
  static final ChatPeople empty = ChatPeople(const []);

  final Map<String, PersonRow> _byId;

  PersonRow? person(String account) => _byId[account];

  /// Every account on the device's people table.
  Iterable<String> get accounts => _byId.keys;

  /// The name to show for [account]; never empty.
  String nameOf(String account) {
    final person = _byId[account];
    if (person == null) return _unknown(account);
    return PersonNaming.displayName(person);
  }

  /// The first word of [nameOf], for "Sam: see you" prefixes in a group.
  String firstNameOf(String account) {
    final full = nameOf(account);
    final space = full.indexOf(' ');
    return space <= 0 ? full : full.substring(0, space);
  }

  /// The line under the name in a header or a list: the number when the name
  /// is not the number, else the `~Helix name`.
  String? secondaryOf(String account) {
    final person = _byId[account];
    if (person == null) return null;
    return HelixPersonNames(
      phoneBookName: _nonEmpty(person.phonebookName),
      nickname: _nonEmpty(person.nickname),
      number: _nonEmpty(person.phoneNumber),
      helixName: _nonEmpty(person.helixName),
    ).secondary;
  }

  bool isBlocked(String account) => _byId[account]?.blocked ?? false;

  bool isVerified(String account) => _byId[account]?.identityVerified ?? false;

  /// A stable colour per person, so the same sender keeps the same colour in
  /// every chat.
  int colorIndexOf(String account) => HelixAvatarModel.colorIndexFor(account);

  ImageProvider? imageOf(String account) {
    final bytes = _byId[account]?.avatarBlob;
    return bytes == null || bytes.isEmpty ? null : _imageFor(account, bytes);
  }

  HelixAvatarModel avatarOf(String account) => HelixAvatarModel(
    name: nameOf(account),
    image: imageOf(account),
    colorIndex: colorIndexOf(account),
  );

  static String _unknown(String account) {
    final short = account.length < 8 ? account : account.substring(0, 8);
    return 'Helix user $short';
  }

  static String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value;
}

// An avatar read from the table is a new byte list on every emission, and an
// image provider is keyed by its bytes' identity, so a naive provider would
// decode the same picture again on every change anywhere in the table. Keep
// the provider while the bytes are equal.
final Map<String, (Uint8List, ImageProvider)> _images = {};

ImageProvider _imageFor(String account, Uint8List bytes) {
  final cached = _images[account];
  if (cached != null && listEquals(cached.$1, bytes)) return cached.$2;
  final provider = MemoryImage(bytes);
  _images[account] = (bytes, provider);
  return provider;
}

/// Everyone the device knows, live.
final chatPeopleProvider = StreamProvider<ChatPeople>((ref) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  yield* gateway.watchPeople().map(ChatPeople.new);
});
