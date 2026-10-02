import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

void main() {
  group('helixInitials', () {
    test('first letters of the first and last word, upper-cased', () {
      expect(helixInitials('Sam Rivera'), 'SR');
      expect(helixInitials('sam'), 'S');
      expect(helixInitials('Mary Jane Watson'), 'MW');
      expect(helixInitials('  lee   chen  '), 'LC');
    });

    test('numbers and empty names fall back to a hash', () {
      expect(helixInitials('+44 7700 900123'), '#');
      expect(helixInitials(''), '#');
      expect(helixInitials('~'), '#');
    });

    test('non-Latin names keep their own letters', () {
      expect(helixInitials('আজ দেখা'), 'আদ');
      expect(helixInitials('مرحبا'), 'م');
    });

    test('a tilde Helix name drops the tilde', () {
      expect(helixInitials('~nadia'), 'N');
    });
  });

  group('HelixAvatarModel.colorIndexFor', () {
    test('is stable and inside the palette', () {
      for (final seed in ['a', 'b', 'account-123', '', 'Sam Rivera']) {
        final i = HelixAvatarModel.colorIndexFor(seed);
        expect(i, HelixAvatarModel.colorIndexFor(seed));
        expect(i, inInclusiveRange(0, 9));
      }
    });
  });

  group('HelixPersonNames follows the people-naming order', () {
    test('phone-book name beats everything', () {
      const names = HelixPersonNames(
        phoneBookName: 'Aisha Khan',
        nickname: 'Ash',
        number: '+44 7700 900456',
        helixName: 'aisha',
      );
      expect(names.display, 'Aisha Khan');
      expect(names.source, HelixNameSource.phoneBook);
      expect(names.secondary, '+44 7700 900456');
    });

    test('then nickname, then number, then ~Helix name', () {
      expect(
        const HelixPersonNames(
          nickname: 'Ash',
          number: '+44 1',
          helixName: 'a',
        ).display,
        'Ash',
      );
      const byNumber = HelixPersonNames(number: '+44 1', helixName: 'a');
      expect(byNumber.display, '+44 1');
      expect(byNumber.secondary, '~a');
      const byHelix = HelixPersonNames(helixName: 'nadia');
      expect(byHelix.display, '~nadia');
      expect(byHelix.secondary, isNull);
    });

    test('empty strings count as missing and nothing at all is neutral', () {
      expect(
        const HelixPersonNames(
          phoneBookName: '',
          nickname: '',
          number: '1',
        ).display,
        '1',
      );
      expect(const HelixPersonNames().display, 'Helix user');
    });
  });

  group('helixRunPositions', () {
    HelixMessage m(
      String id, {
      bool out = false,
      String author = 'a',
      int at = 0,
    }) => HelixMessage(
      id: id,
      outgoing: out,
      authorId: author,
      sentAtMs: at,
      timeLabel: '',
      content: const HelixTextContent('x'),
    );

    test('groups consecutive messages from one sender', () {
      final p = helixRunPositions([m('1'), m('2', at: 1), m('3', at: 2)]);
      expect(p, [
        HelixRunPosition.first,
        HelixRunPosition.middle,
        HelixRunPosition.last,
      ]);
    });

    test('a different sender or a long gap starts a new run', () {
      final p = helixRunPositions([
        m('1'),
        m('2', author: 'b', at: 1),
        m('3', author: 'b', at: 2 + HelixChatMetrics.runGapMs + 1),
      ]);
      expect(p, [
        HelixRunPosition.single,
        HelixRunPosition.single,
        HelixRunPosition.single,
      ]);
    });

    test('incoming and outgoing never share a run', () {
      final p = helixRunPositions([m('1'), m('2', out: true, at: 1)]);
      expect(p, everyElement(HelixRunPosition.single));
    });

    test('empty list', () => expect(helixRunPositions(const []), isEmpty));
  });

  group('value equality', () {
    test('equal view models compare equal and hash alike', () {
      const a = HelixChatListItem(
        id: '1',
        title: 'Sam',
        avatar: HelixAvatarModel(name: 'Sam'),
        unreadCount: 2,
        preview: HelixChatPreview(text: 'hi'),
      );
      const b = HelixChatListItem(
        id: '1',
        title: 'Sam',
        avatar: HelixAvatarModel(name: 'Sam'),
        unreadCount: 2,
        preview: HelixChatPreview(text: 'hi'),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a ==
            const HelixChatListItem(
              id: '1',
              title: 'Sam',
              avatar: HelixAvatarModel(name: 'Sam'),
              unreadCount: 3,
            ),
        isFalse,
      );
    });

    test('list fields compare by element', () {
      const a = HelixMediaContent([
        HelixMediaItem(),
        HelixMediaItem(isVideo: true),
      ]);
      const b = HelixMediaContent([
        HelixMediaItem(),
        HelixMediaItem(isVideo: true),
      ]);
      const c = HelixMediaContent([HelixMediaItem()]);
      expect(a, b);
      expect(a == c, isFalse);
    });

    test('different runtime types never compare equal', () {
      expect(
        const HelixDateSeparatorItem('x') == const HelixUnreadDividerItem(1),
        isFalse,
      );
    });
  });

  group('helixTextDirectionOf', () {
    test('first strong letter decides', () {
      expect(helixTextDirectionOf('hello'), TextDirection.ltr);
      expect(helixTextDirectionOf('مرحبا بك'), TextDirection.rtl);
      expect(helixTextDirectionOf('שלום'), TextDirection.rtl);
      expect(helixTextDirectionOf('আজ দেখা হবে'), TextDirection.ltr);
      expect(helixTextDirectionOf('12:30 مرحبا'), TextDirection.rtl);
    });

    test('digits and emoji alone have no direction', () {
      expect(helixTextDirectionOf('1234'), isNull);
      expect(helixTextDirectionOf('👍'), isNull);
      expect(helixTextDirectionOf(''), isNull);
    });
  });

  test('HelixQrMatrix indexes row-major', () {
    final m = HelixQrMatrix(2, const [true, false, false, true]);
    expect(m.at(0, 0), isTrue);
    expect(m.at(1, 0), isFalse);
    expect(m.at(0, 1), isFalse);
    expect(m.at(1, 1), isTrue);
  });

  test('preview labels and icons cover every kind', () {
    for (final kind in HelixPreviewKind.values) {
      if (kind == HelixPreviewKind.text) {
        expect(helixPreviewLabel(kind), isEmpty);
        expect(helixPreviewIcon(kind), isNull);
      } else {
        expect(helixPreviewLabel(kind), isNotEmpty, reason: '$kind');
        expect(helixPreviewIcon(kind), isNotNull, reason: '$kind');
      }
    }
  });

  test('default message actions follow edit and delete rules', () {
    List<String> ids({
      bool outgoing = false,
      bool edit = false,
      bool everyone = false,
      bool text = true,
    }) => helixDefaultMessageActions(
      outgoing: outgoing,
      canEdit: edit,
      canDeleteForEveryone: everyone,
      hasText: text,
    ).map((a) => a.id).toList();

    expect(ids(), isNot(contains(HelixMessageActionIds.edit)));
    expect(ids(), isNot(contains(HelixMessageActionIds.info)));
    expect(ids(), isNot(contains(HelixMessageActionIds.deleteForEveryone)));
    expect(
      ids(outgoing: true, edit: true, everyone: true),
      containsAll([
        HelixMessageActionIds.edit,
        HelixMessageActionIds.info,
        HelixMessageActionIds.deleteForEveryone,
      ]),
    );
    expect(ids(text: false), isNot(contains(HelixMessageActionIds.copy)));
  });
}
