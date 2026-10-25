part of '../bodies.dart';

/// The sized field reads of the content bodies.
///
/// A body asks for a field's role, not its limit: `json.id('group_id')`
/// cannot be written without the cap, which is what the raw reader calls
/// allowed. A list's count stays the caller's, because the contract counts
/// different lists differently — but here it is a required argument, so
/// forgetting it is a compile error rather than the reader's default.
///
/// A bare name is a required field and `opt...` a missing-or-null one.
/// Emptiness follows the role: an id, a name and a url must not be blank,
/// while a label, text, caption, emoji and a card's numbers may be.
extension Bounded on JsonReader {
  /// An identifier on the wire: [ContentLimits.maxIdLength], non-empty.
  String id(String field) =>
      nonEmpty(field, maxLength: ContentLimits.maxIdLength);

  String? optId(String field) =>
      optString(field, maxLength: ContentLimits.maxIdLength);

  /// At most [maxItems] identifiers.
  List<String> ids(String field, {required int maxItems}) =>
      strings(field, maxItems: maxItems, maxLength: ContentLimits.maxIdLength);

  /// A one-line value that must be there: [ContentLimits.maxNameLength],
  /// non-empty.
  String name(String field) =>
      nonEmpty(field, maxLength: ContentLimits.maxNameLength);

  String? optName(String field) =>
      optString(field, maxLength: ContentLimits.maxNameLength);

  /// A one-line value a peer writes about something, which may be blank.
  String label(String field) =>
      string(field, maxLength: ContentLimits.maxNameLength);

  /// Message text: [ContentLimits.maxTextLength]; empty is legal (a sticker
  /// or a media-only send has none).
  String text(String field) =>
      string(field, maxLength: ContentLimits.maxTextLength);

  String? optText(String field) =>
      optString(field, maxLength: ContentLimits.maxTextLength);

  String caption(String field) =>
      string(field, maxLength: ContentLimits.maxCaptionLength);

  String? optCaption(String field) =>
      optString(field, maxLength: ContentLimits.maxCaptionLength);

  String url(String field) =>
      nonEmpty(field, maxLength: ContentLimits.maxUrlLength);

  String emoji(String field) =>
      string(field, maxLength: ContentLimits.maxEmojiLength);

  String? optEmoji(String field) =>
      optString(field, maxLength: ContentLimits.maxEmojiLength);

  /// The numbers of one contact card; a card may have none.
  List<String> optNumbers(String field) => optStrings(
    field,
    maxItems: ContentLimits.maxContactNumbers,
    maxLength: ContentLimits.maxNumberLength,
  );

  /// Objects of one shape, with the item count required rather than defaulted.
  List<T> many<T>(
    String field,
    T Function(JsonReader item) decode, {
    required int maxItems,
  }) => objects(field, decode, maxItems: maxItems);

  /// [many], where a missing field is an empty list.
  List<T> optMany<T>(
    String field,
    T Function(JsonReader item) decode, {
    required int maxItems,
  }) => optObjects(field, decode, maxItems: maxItems);
}
