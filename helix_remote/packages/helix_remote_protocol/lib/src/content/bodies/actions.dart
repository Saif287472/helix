part of '../bodies.dart';

/// The bodies that act on another message instead of being one (CONTENT_V2.md
/// §3).

final class ReactionBody extends ContentBody {
  const ReactionBody({
    required this.target,
    required this.emoji,
    this.remove = false,
  });

  static const typeName = 'reaction';

  final MessageRef target;
  final String emoji;
  final bool remove;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'target': target.toJson(),
    'emoji': emoji,
    if (remove) 'remove': true,
  };

  factory ReactionBody.fromJson(JsonReader json) => ReactionBody(
    target: MessageRef.fromJson(json.object('target')),
    emoji: json.emoji('emoji'),
    remove: json.flag('remove'),
  );
}

final class EditBody extends ContentBody {
  const EditBody({required this.target, this.text, this.caption});

  static const typeName = 'edit';

  final MessageRef target;

  /// New text of a `text` message.
  final String? text;

  /// New caption of a `media` message.
  final String? caption;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() =>
      compact({'target': target.toJson(), 'text': text, 'caption': caption});

  factory EditBody.fromJson(JsonReader json) {
    final edit = EditBody(
      target: MessageRef.fromJson(json.object('target')),
      text: json.optText('text'),
      caption: json.optCaption('caption'),
    );
    if ((edit.text == null) == (edit.caption == null)) {
      throw ProtocolFormatException(
        'edit needs text or caption',
        path: json.path,
      );
    }
    return edit;
  }
}

final class DeleteBody extends ContentBody {
  const DeleteBody({required this.target});

  static const typeName = 'delete';

  final MessageRef target;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'target': target.toJson()};

  factory DeleteBody.fromJson(JsonReader json) =>
      DeleteBody(target: MessageRef.fromJson(json.object('target')));
}

final class PollVoteBody extends ContentBody {
  const PollVoteBody({required this.target, required this.optionIds});

  static const typeName = 'poll_vote';

  final MessageRef target;

  /// Empty withdraws the vote.
  final List<String> optionIds;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'target': target.toJson(), 'option_ids': optionIds};

  factory PollVoteBody.fromJson(JsonReader json) => PollVoteBody(
    target: MessageRef.fromJson(json.object('target')),
    // A vote names options of this poll: never more than the poll has, and an
    // over-long id is not one of them. Duplicates are dropped where the vote
    // is applied.
    optionIds: json.ids('option_ids', maxItems: ContentLimits.maxPollOptions),
  );
}

enum RsvpState implements WireEnum {
  going('going'),
  maybe('maybe'),
  declined('declined');

  const RsvpState(this.wire);

  @override
  final String wire;
}

final class RsvpBody extends ContentBody {
  const RsvpBody({
    required this.target,
    required this.state,
    this.plusOne = false,
  });

  static const typeName = 'rsvp';

  final MessageRef target;
  final RsvpState state;
  final bool plusOne;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'target': target.toJson(),
    'state': state.wire,
    'plus_one': plusOne,
  };

  factory RsvpBody.fromJson(JsonReader json) => RsvpBody(
    target: MessageRef.fromJson(json.object('target')),
    state: json.enumValue('state', RsvpState.values),
    plusOne: json.flag('plus_one'),
  );
}

enum ReceiptKind implements WireEnum {
  delivered('delivered'),
  read('read'),
  viewed('viewed');

  const ReceiptKind(this.wire);

  @override
  final String wire;
}

final class ReceiptBody extends ContentBody {
  const ReceiptBody({required this.kind, required this.ids});

  static const typeName = 'receipt';

  final ReceiptKind kind;
  final List<String> ids;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'kind': kind.wire, 'ids': ids};

  factory ReceiptBody.fromJson(JsonReader json) {
    final ids = json.ids('ids', maxItems: ContentLimits.maxIdsPerReceipt);
    if (ids.isEmpty) {
      throw ProtocolFormatException('bad id count', path: '${json.path}.ids');
    }
    return ReceiptBody(
      kind: json.enumValue('kind', ReceiptKind.values),
      ids: ids,
    );
  }
}
