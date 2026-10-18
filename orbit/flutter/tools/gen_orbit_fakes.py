"""Write packages/orbit_ui/lib/src/fakes/orbit_fakes.dart: the prototype's
sample data (prototype/js/data.js) as the Flutter view models, so the kit
sheets and the preview's screens draw the same people, chats and calls.

data.js is run in Node and dumped as JSON; nothing is typed by hand.

  python orbit/flutter/tools/gen_orbit_fakes.py [--check]
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FLUTTER = os.path.dirname(HERE)
PROTOTYPE = os.path.join(os.path.dirname(FLUTTER), 'prototype')
OUT = os.path.join(FLUTTER, 'packages', 'orbit_ui', 'lib', 'src', 'fakes', 'orbit_fakes.dart')

DUMP = r"""
const fs = require('fs');
const src = fs.readFileSync(process.argv[1], 'utf8');
const Data = new Function(src + '; return Data;')();
const pick = ({ me, people, chats, archived, calls, conversations, wave }) => ({ me, people, chats, archived, calls, conversations, wave });
process.stdout.write(JSON.stringify(pick(Data)));
"""


def data():
    js = os.path.join(PROTOTYPE, 'js', 'data.js')
    out = subprocess.run(['node', '-e', DUMP, js], check=True, capture_output=True)
    return json.loads(out.stdout.decode('utf-8'))


def s(v):
    """A Dart string literal."""
    return "'" + v.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


def camel(name):
    parts = re.split(r'[-:]', name)
    return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])


def colour_index(seed):
    """UI.colorIndexFor in js/ui.js (and HelixAvatarModel.colorIndexFor):
    FNV-1a with Math.imul, kept to 31 bits, over the 8-colour palette."""
    h = 0x811c9dc5
    for ch in str(seed):
        code = ord(ch)
        if code > 0xFFFF:  # JavaScript sees the first UTF-16 unit
            code = 0xD800 + ((code - 0x10000) >> 10)
        h = ((h ^ code) * 0x01000193) & 0x7fffffff
    return h % 8


def avatar(a):
    seed = a.get('seed') or a['name']
    index = a['color'] if a.get('color') is not None else colour_index(seed)
    args = [f"name: {s(a['name'])}", f'colorIndex: {index}']
    if a.get('group'):
        args.append('isGroup: true')
    return f"HelixAvatarModel({', '.join(args)})"


def preview(p):
    if not p:
        return None
    args = [f"text: {s(p.get('text', ''))}", f"kind: HelixPreviewKind.{p.get('kind', 'text')}"]
    if p.get('senderPrefix'):
        args.append(f"senderPrefix: {s(p['senderPrefix'])}")
    if p.get('status'):
        args.append(f"status: HelixDeliveryStatus.{p['status']}")
    if p.get('isDraft'):
        args.append('isDraft: true')
    return f"HelixChatPreview({', '.join(args)})"


def chat(c):
    args = [f"id: {s(c['id'])}", f"title: {s(c['title'])}", f"avatar: {avatar(c['avatar'])}"]
    pv = preview(c.get('preview'))
    if pv:
        args.append(f'preview: {pv}')
    if c.get('timeLabel'):
        args.append(f"timeLabel: {s(c['timeLabel'])}")
    for key in ('unreadCount',):
        if c.get(key):
            args.append(f'{key}: {c[key]}')
    for key in ('hasMention', 'markedUnread', 'pinned', 'muted', 'archived', 'online', 'verified'):
        if c.get(key):
            args.append(f'{key}: true')
    if c.get('typingLabel'):
        args.append(f"typingLabel: {s(c['typingLabel'])}")
    return f"HelixChatListItem({', '.join(args)})"


def call(c):
    args = [f"id: {s(c['id'])}", f"title: {s(c['title'])}", f"avatar: {avatar(c['avatar'])}",
            f"direction: HelixCallDirection.{c['direction']}", f"timeLabel: {s(c['timeLabel'])}"]
    if c.get('video'):
        args.append('video: true')
    if c.get('count', 1) != 1:
        args.append(f"count: {c['count']}")
    return f"HelixCallLogItem({', '.join(args)})"


def person(p):
    n = p['names']
    names = ', '.join(f'{k}: {s(n[k])}' for k in ('phoneBookName', 'nickname', 'number', 'helixName') if n.get(k))
    args = [f"id: {s(p['id'])}", f'names: HelixPersonNames({names})']
    if p.get('about'):
        args.append(f"about: {s(p['about'])}")
    for key in ('online', 'blocked'):
        if p.get(key):
            args.append(f'{key}: true')
    return f"HelixPersonItem({', '.join(args)})"


def camel_icon(name):
    return 'OrbitIcons.' + camel(name)


def colour_of(index, name):
    return index if index is not None else colour_index(name or '')


def utf16(text):
    return len(text.encode('utf-16-le')) // 2


def content(c):
    t = c['type']
    if t == 'text':
        args = [s(c['text'])]
        ms = []
        for name in c.get('mentions', []):
            needle = '@' + name
            i = c['text'].find(needle)
            while i >= 0:
                ms.append(f'HelixTextRange({utf16(c["text"][:i])}, {utf16(needle)})')
                i = c['text'].find(needle, i + 1)
        if ms:
            args.append(f"mentions: [{', '.join(ms)}]")
        lp = c.get('linkPreview')
        if lp:
            url = re.search(r'https?://\S+', c['text'])
            la = [f"url: {s(url.group(0) if url else 'https://' + lp['host'])}"]
            if lp.get('title'):
                la.append(f"title: {s(lp['title'])}")
            if lp.get('description'):
                la.append(f"description: {s(lp['description'])}")
            args.append(f"linkPreview: HelixLinkPreview({', '.join(la)})")
        return f"HelixTextContent({', '.join(args)})"
    if t == 'poll':
        return f"HelixPollContent(question: {s(c['question'])}, options: [{', '.join(s(o) for o in c['options'])}])"
    if t == 'media':
        items = []
        for it in c['items']:
            a = []
            for k in ('width', 'height'):
                if it.get(k):
                    a.append(f'{k}: {it[k]}')
            for k in ('isVideo', 'isGif'):
                if it.get(k):
                    a.append(f'{k}: true')
            if it.get('durationLabel'):
                a.append(f"durationLabel: {s(it['durationLabel'])}")
            if it.get('transfer'):
                a.append(f"transfer: HelixTransferState.{it['transfer']}")
                if it['transfer'] in ('downloading', 'uploading'):
                    a.append(f"progress: {it.get('progress', 0.3)}")
            if it.get('sizeLabel'):
                a.append(f"sizeLabel: {s(it['sizeLabel'])}")
            a.append(f"swatch: {s(it.get('photo') or 'ph-a')}")
            items.append(f"HelixMediaItem({', '.join(a)})")
        cap = f", caption: {s(c['caption'])}" if c.get('caption') else ''
        return f"HelixMediaContent([{', '.join(items)}]{cap})"
    if t == 'audio':
        a = [f"durationLabel: {s(c['durationLabel'])}"]
        if c.get('waveform'):
            a.append(f"waveform: Uint8List.fromList(const [{', '.join(str(v) for v in c['waveform'])}])")
        if c.get('progress'):
            a.append(f"progress: {c['progress']}")
        if c.get('speed') not in (None, 1):
            a.append(f"speed: {c['speed']}")
        if c.get('positionLabel'):
            a.append(f"positionLabel: {s(c['positionLabel'])}")
        for k in ('playing', 'played'):
            if c.get(k):
                a.append(f'{k}: true')
        if c.get('isVoiceNote') is False:
            a.append('isVoiceNote: false')
        if c.get('transfer'):
            a.append(f"transfer: HelixTransferState.{c['transfer']}")
        if c.get('title'):
            a.append(f"title: {s(c['title'])}")
        return f"HelixAudioContent({', '.join(a)})"
    if t == 'document':
        a = [f"name: {s(c['name'])}", f"sizeLabel: {s(c.get('sizeLabel', ''))}",
             f"typeLabel: {s(c.get('typeLabel', ''))}"]
        if c.get('transfer'):
            a.append(f"transfer: HelixTransferState.{c['transfer']}")
        if c.get('progress') is not None:
            a.append(f"progress: {c['progress']}")
        if c.get('caption'):
            a.append(f"caption: {s(c['caption'])}")
        return f"HelixDocumentContent({', '.join(a)})"
    if t == 'location':
        return f"HelixLocationContent(label: {s(c.get('label', ''))}, address: {s(c.get('address', ''))})"
    if t == 'contact':
        on = ', onHelix: true' if c.get('onHelix') else ''
        return f"HelixContactContent(name: {s(c['name'])}, detail: {s(c.get('detail', ''))}{on})"
    if t == 'viewOnce':
        return (f"HelixViewOnceContent(isVideo: {str(bool(c.get('isVideo'))).lower()}, "
                f"opened: {str(bool(c.get('opened'))).lower()})")
    if t == 'placeholder':
        return f"HelixPlaceholderContent(HelixPlaceholderKind.{c['kind']})"
    raise ValueError(t)


def message(m):
    a = [f"id: {s(m['id'])}", f"outgoing: {str(m['outgoing']).lower()}", f"content: {content(m['content'])}",
         f"timeLabel: {s(m['timeLabel'])}"]
    if m.get('authorId'):
        a.append(f"authorId: {s(m['authorId'])}")
    if m.get('authorName'):
        a.append(f"authorName: {s(m['authorName'])}")
    a.append(f"authorColorIndex: {colour_of(m.get('authorColorIndex'), m.get('authorName'))}")
    if m.get('sentAt'):
        a.append(f"sentAtMs: {m['sentAt'] * 60000}")
    a.append(f"status: HelixDeliveryStatus.{m.get('status', 'sent')}")
    q = m.get('reply')
    if q:
        qa = [f"authorName: {s(q['authorName'])}", f"text: {s(q.get('text', ''))}",
              f"authorColorIndex: {colour_of(q.get('authorColorIndex'), q['authorName'])}"]
        if q.get('kind'):
            qa.append(f"kind: HelixPreviewKind.{q['kind']}")
        if q.get('missing'):
            qa.append('missing: true')
        a.append(f"reply: HelixReplyQuote({', '.join(qa)})")
    for k in ('forwarded', 'edited'):
        if m.get(k):
            a.append(f'{k}: true')
    if m.get('reactions'):
        rs = [f"HelixReaction(emoji: {s(r['emoji'])}, count: {r['count']}{', mine: true' if r.get('mine') else ''})"
              for r in m['reactions']]
        a.append(f"reactions: [{', '.join(rs)}]")
    if m.get('expiresLabel'):
        a.append(f"expiresLabel: {s(m['expiresLabel'])}")
    return f"HelixMessage({', '.join(a)})"


def item(it, i):
    k = it['kind']
    if k == 'day':
        return f"HelixDateSeparatorItem({s(it['label'])})"
    if k == 'unread':
        return f"HelixUnreadDividerItem({it['count']})"
    if k == 'notice':
        tone = {'warn': 'warn', 'calllog missed': 'missedCall'}.get(it.get('tone') or '', 'plain')
        icon = f", icon: {camel_icon(it['icon'])}" if it.get('icon') else ''
        return f"HelixSystemNoticeItem('n{i}', {s(it['text'])}{icon}, tone: HelixNoticeTone.{tone})"
    if k == 'msg':
        return f"HelixMessageItem({message(it['m'])})"
    raise ValueError(k)


def formatted(text):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, 'orbit_fakes.dart')
        with open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
        subprocess.run(['dart', 'format', path], check=True, capture_output=True, shell=os.name == 'nt')
        with open(path, encoding='utf-8') as f:
            return f.read()


def main():
    d = data()
    people = d['people']
    out = [
        '// GENERATED by tools/gen_orbit_fakes.py from prototype/js/data.js. Do not',
        '// edit by hand.',
        '//',
        '// The timelines hold waveforms, which are not const, so the analyzer is told',
        '// not to ask for const there.',
        '// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables',
        '',
        "import 'dart:typed_data';",
        '',
        "import 'package:orbit_ui/src/fakes/timeline_runs.dart';",
        "import 'package:orbit_ui/src/icons/orbit_icons.dart';",
        "import 'package:orbit_ui/src/models/view_models.dart';",
        '',
        "/// The prototype's sample data (`Data` in `prototype/js/data.js`) as view",
        '/// models: what the kit sheets and the preview draw.',
        'abstract final class OrbitFakes {',
        f"  /// `Data.me`: you.",
        f"  static const meName = {s(d['me']['name'])};",
        '',
        "  /// `Data.wave`: the sample waveform (0-255 per bar).",
        f"  static const wave = <int>[{', '.join(str(v) for v in d['wave'])}];",
        '',
        '  /// `Data.people`, by id.',
    ]
    for pid, p in people.items():
        out.append(f'  static const {camel(pid)} = {person(p)};')
    out += ['', '  /// `Data.chats`: the chat list, in order.', '  static const chats = <HelixChatListItem>[']
    out += [f'    {chat(c)},' for c in d['chats']]
    out += ['  ];', '', '  /// `Data.archived`.', '  static const archived = <HelixChatListItem>[']
    out += [f'    {chat(c)},' for c in d['archived']]
    out += ['  ];', '', '  /// `Data.calls`: the call log, in order.', '  static const calls = <HelixCallLogItem>[']
    out += [f'    {call(c)},' for c in d['calls']]
    out += ['  ];', '', "  /// `Data.conversations`: each chat's timeline, oldest first, with the",
            '  /// run positions the prototype works out (`UI.runPositions`).',
            '  static final conversations = <String, List<HelixTimelineItem>>{']
    for cid, conv in d['conversations'].items():
        items = ', '.join(item(it, i) for i, it in enumerate(conv['items']))
        out.append(f'    {s(cid)}: orbitWithRuns([{items}]),')
    out += ['  };', '}', '']
    text = formatted('\n'.join(out))
    if '--check' in sys.argv:
        same = os.path.exists(OUT) and open(OUT, encoding='utf-8').read() == text
        sys.exit(0 if same else 'orbit_fakes.dart is out of date: run tools/gen_orbit_fakes.py')
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w', encoding='utf-8', newline='\n').write(text)
    print(f"{len(d['chats'])} chats, {len(d['archived'])} archived, {len(d['calls'])} calls -> {OUT}")


if __name__ == '__main__':
    main()
