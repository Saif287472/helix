"""Orbit themes: the single source for every theme's tokens.

    python tools/themes.py        -> writes css/themes.css and js/themes.js,
                                     prints a contrast report (fails loudly)

Each theme gives its core colours, fonts, shapes, chat pattern, icon weight
and effects; the semantic tokens (soft/line tints, hover, inverse, glass...)
are derived from those. The Flutter port can read the same table.
Palettes draw on Figma's "100 color combinations" (Blue eclipse, Evening
rose, Cotton candy skies, Golden taupe, Technicolor dream, Neon noir, Mossy
hollow) and keep to one accent plus at most one secondary per theme.
"""
import os
import re
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ------------------------------------------------------------- colour maths
def rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexc(c):
    return '#%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):
    """t of b over a."""
    ca, cb = rgb(a), rgb(b)
    return hexc(tuple(ca[i] + (cb[i] - ca[i]) * t for i in range(3)))


def rgba(h, a):
    r, g, b = rgb(h)
    return f'rgba({r}, {g}, {b}, {a})'


def lum(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def fit_ink(hue, bg, dark, target=4.6):
    """A text colour in hue's family that reads on bg."""
    for i in range(0, 41):
        t = i / 40
        c = mix(hue, '#FFFFFF' if dark else '#000000', t)
        if contrast(c, bg) >= target:
            return c
    return '#FFFFFF' if dark else '#000000'


def status(name, hue, surface, dark):
    """Soft tint and border from the hue; the text colour is fitted to read on the tint."""
    soft = mix(surface, hue, 0.16 if dark else 0.12)
    text = hue if contrast(hue, soft) >= 4.6 else fit_ink(hue, soft, dark)
    return {name: text, f'{name}-soft': soft, f'{name}-line': mix(surface, hue, 0.4 if dark else 0.3)}


def fit_bg(colour, text, target=4.6):
    """Darken (or lighten) a background in its own hue until text reads on it."""
    dark_text = lum(text) < 0.4
    for i in range(0, 41):
        c = mix(colour, '#FFFFFF' if dark_text else '#000000', i / 40)
        if contrast(text, c) >= target:
            return c
    return colour


def svg_url(svg):
    return "url(\"data:image/svg+xml," + urllib.parse.quote(svg, safe=" =:/',.()-") + "\")"


# ------------------------------------------------------------- chat patterns
# A pattern is a NAME plus PARAMETERS, never a finished CSS string. The same
# record generates `--chat-pattern` here and the JSON the Flutter port reads,
# so a theme turns a pattern on by name and a downloaded theme pack (Part C)
# can ask for one it has never seen. Only the numbers are theme data; the
# artwork below is the app's, and its tile size is part of the drawing, not a
# free parameter.
#
#   none       no pattern: the chat background is --chat-bg.
#   grain      tiled fractal noise (bloom's, papyrus's, jungle's).
#   hearts     tiled marks (mochi's).
#   neon-grid  one 1px rule each way per cell (arcade's).
#   scanlines  a repeating line, period built in, no tile (terminal's, metal's).
#   contours   five stroked curves (field's, ocean's).
#
# The viewer's own "Dot grid" and "Orbit lines" (body.bg-dots) are NOT here:
# they are preview affordances, not theme data, so no theme can select them.

GRAIN_SVG = (
    "<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'>"
    "<filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='3' stitchTiles='stitch'/>"
    "<feColorMatrix values='0 0 0 0 {r} 0 0 0 0 {g} 0 0 0 0 {b} 0 0 0 {a} 0'/></filter>"
    "<rect width='100%' height='100%' filter='url(#n)'/></svg>")

HEARTS_SVG = (
    "<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'>"
    "<path d='M16 20c-2-3-7-2-7 2 0 3 4 5 7 8 3-3 7-5 7-8 0-4-5-5-7-2z' fill='#FFB3D1' fill-opacity='.4'/>"
    "<path d='M46 40l1.6 3.4 3.4 1.6-3.4 1.6L46 50l-1.6-3.4L41 45l3.4-1.6z' fill='#B9A2FF' fill-opacity='.45'/>"
    "<circle cx='50' cy='14' r='1.6' fill='#7FD0F5' fill-opacity='.5'/></svg>")

CONTOUR_SVG = (
    "<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'>"
    "<g fill='none' stroke='{stroke}' stroke-width='{width}'>"
    "<path d='M-10 110c25-45 65-55 100-32s70 12 80-22 40-30 60-10'/>"
    "<path d='M-10 150c35-32 78-38 112-16s62 6 88-26 30-22 40-14'/>"
    "<path d='M-10 70c28-28 60-33 88-12s56 2 78-32 40-20 70-8'/>"
    "<path d='M-10 195c38-22 82-28 115-6s66 10 104-16'/>"
    "<path d='M-10 30c30-20 66-24 96-4s60 0 80-26'/></g></svg>")


def pattern_css(p):
    """`(kind, params)` -> the CSS value for `--chat-pattern`."""
    kind, q = p
    if kind == 'none':
        return 'none'
    if kind == 'grain':
        return svg_url(GRAIN_SVG.format(r=q['r'], g=q['g'], b=q['b'], a=q['a']))
    if kind == 'hearts':
        return svg_url(HEARTS_SVG)
    if kind == 'neonGrid':
        return (f'linear-gradient({rgba(q["h"], q["ha"])} 1px, transparent 1px), '
                f'linear-gradient(90deg, {rgba(q["v"], q["va"])} 1px, transparent 1px)')
    if kind == 'scanlines':
        return (f'repeating-linear-gradient(0deg, {rgba(q["colour"], q["a"])} 0 {q["thickness"]}px, '
                f'transparent {q["thickness"]}px {q["period"]}px)')
    if kind == 'contours':
        return svg_url(CONTOUR_SVG.format(stroke=q['stroke'], width=q['width']))
    raise ValueError(f'unknown chat pattern {kind!r}: a theme would draw nothing')


def pattern_size_css(p):
    """`(kind, params)` -> the CSS value for `--chat-pattern-size`."""
    size = p[1].get('size')
    if size is None:
        return 'auto'
    return '%dpx %dpx' % (size[0], size[1])


# ---------------------------------------------------------- theme effects
# Decorative behaviour, as data. Eight of the eleven themes switch on effects the
# token table cannot express: a blinking cursor, ornaments beside a date, a
# stripe down the edge of a bubble, a glow, a notched corner. Until now all of
# that lived in a raw CSS string per theme, which meant the Flutter port had to
# hand-copy it into Dart and a downloadable theme pack (Part C) could not ask
# for any of it.
#
# So a theme names its effects, each with parameters, and `effect_css` renders
# the record back to the exact CSS the prototype had. The app ships the effect
# *types*; a pack carries only their settings.
#
#   wordmarkGlow   a drop shadow on the wordmark          arcade, terminal, ocean
#   bubbleGlow     a shadow on each kind of bubble        arcade
#   bubbleStripe   a coloured stripe down a bubble edge   field
#   cursor         a blinking glyph after the wordmark    terminal
#   ornament       a glyph beside a date or a group       mochi, papyrus, terminal, field
#   cardRing       an inset double rule on a card         papyrus
#   cornerClip     a notched corner, square radii         arcade, metal
#   wordmarkItalic italic wordmark                        bloom
#   dayLabel       a different face and size for dates    bloom
#   bubbleWeight   a bolder bubble                        mochi
#   dockBorder     a border on the dock                   mochi
#   pagePattern    the chat pattern behind a page         papyrus
#   baseFontSize   the theme's own root size              papyrus
#   eyebrowColour  the colour of eyebrows and dates       arcade, metal
#
# A colour is either what the CSS says today (`lit`) or a token it reads
# (`tok`). Nothing is re-tinted here: a colour that ought to become a token is a
# design change for the owner, not something a refactor may decide.

EFFECT_KINDS = frozenset((
    'wordmarkGlow', 'bubbleGlow', 'bubbleStripe', 'cursor', 'ornament',
    'cardRing', 'cornerClip', 'wordmarkItalic', 'dayLabel', 'bubbleWeight',
    'dockBorder', 'pagePattern', 'baseFontSize', 'eyebrowColour',
))


def lit(colour, alpha=None):
    """A literal colour, exactly as the CSS writes it today."""
    return {'kind': 'literal', 'colour': colour, 'alpha': alpha}


def tok(name):
    """A token the CSS reads, without its `var(--...)` wrapper."""
    return {'kind': 'token', 'name': name}


def paint(c, theme_id):
    """The CSS value for an effect colour."""
    if c['kind'] == 'token':
        return 'var(--%s)' % c['name']
    if c.get('alpha') is None:
        return c['colour']
    return rgba(c['colour'], c['alpha'])


def sel(theme_id, selectors):
    """`[data-theme="x"] .a, [data-theme="x"] .b` - the theme's own rules."""
    return ', '.join('[data-theme="%s"] %s' % (theme_id, s) for s in selectors)


def rule(selector, body):
    return '%s { %s }' % (selector, body)


def shadow_css(dx, dy, blur, colour, theme_id):
    return '%d %d %dpx %s' % (dx, dy, blur, paint(colour, theme_id))


def effect_css(e):
    """One effect record -> the CSS line(s) the prototype emits for it."""
    kind, theme_id = e['kind'], e['theme']
    q = e['params']

    if kind == 'wordmarkGlow':
        return rule(sel(theme_id, ['.wordmark']),
                    'filter: drop-shadow(%s);'
                    % shadow_css(q['dx'], q['dy'], q['blur'], q['colour'], theme_id))

    if kind == 'bubbleGlow':
        return '\n'.join(
            rule(sel(theme_id, ['.msg.%s .bubble' % side]),
                 'box-shadow: %s;' % shadow_css(q[side]['dx'], q[side]['dy'],
                                                q[side]['blur'], q[side]['colour'],
                                                theme_id))
            for side in ('in', 'out'))

    if kind == 'bubbleStripe':
        return '\n'.join(
            rule(sel(theme_id, ['.msg.%s .bubble' % side]),
                 'border-%s: %dpx solid %s;'
                 % (q[side]['edge'], q[side]['width'], paint(q[side]['colour'], theme_id)))
            for side in ('in', 'out'))

    if kind == 'cursor':
        return rule(sel(theme_id, ['.wordmark::after']),
                    'content: "%s"; -webkit-text-fill-color: %s; '
                    'animation: blink %s infinite;'
                    % (q['glyph'], paint(q['colour'], theme_id), q['period']))

    if kind == 'ornament':
        target = q['target']
        if target == 'group':
            selectors = ['.group-title.eyebrow::%s' % q['pseudo']]
        else:
            selectors = ['.day span::%s' % q['pseudo']] \
                if q['target'] == 'day' else ['.wordmark::%s' % q['pseudo']]
        body = 'content: "%s";' % q['glyph']
        if q.get('colour') is not None:
            prop = '-webkit-text-fill-color' if q.get('fill') else 'color'
            body += ' %s: %s;' % (prop, paint(q['colour'], theme_id))
        if q.get('size') is not None:
            body += ' font-size: %s;' % q['size']
        return rule(sel(theme_id, selectors), body)

    if kind == 'cardRing':
        rings = ', '.join('inset 0 0 0 %dpx var(--%s)' % (r['width'], r['token'])
                          for r in q['rings'])
        return rule(sel(theme_id, q['targets']), 'box-shadow: %s;' % rings)

    if kind == 'cornerClip':
        n = q['notch']
        poly = ('polygon(%dpx 0, 100%% 0, 100%% calc(100%% - %dpx), '
                'calc(100%% - %dpx) 100%%, 0 100%%, 0 %dpx)' % (n, n, n, n))
        body = 'clip-path: %s; border-radius: %s; box-shadow: %s;' % (
            poly, q['radius'], q['shadow'])
        return rule(sel(theme_id, q['targets']), body)

    if kind == 'wordmarkItalic':
        return rule(sel(theme_id, ['.wordmark']), 'font-style: italic;')

    if kind == 'dayLabel':
        return rule(sel(theme_id, ['.day span']),
                    'font-family: var(--font-display); font-style: italic; '
                    'text-transform: none; letter-spacing: 0; font-size: %s;'
                    % q['size'])

    if kind == 'bubbleWeight':
        return rule(sel(theme_id, ['.bubble']), 'font-weight: %d;' % q['weight'])

    if kind == 'dockBorder':
        return rule(sel(theme_id, ['.dock']),
                    'border: %dpx solid %s;' % (q['width'], paint(q['colour'], theme_id)))

    if kind == 'pagePattern':
        return rule(sel(theme_id, ['.page']),
                    'background-image: var(--chat-pattern); '
                    'background-size: var(--chat-pattern-size);')

    if kind == 'baseFontSize':
        return rule(sel(theme_id, ['.phone-screen']) + ', [data-theme="%s"]' % theme_id,
                    'font-size: %s;' % q['size'])

    if kind == 'eyebrowColour':
        return rule(sel(theme_id, q['targets']),
                    'color: var(--%s);' % q['token'])

    raise ValueError('unknown effect %r: a downloaded pack would draw nothing'
                     % kind)


def effects_css(t):
    """Every effect of a theme, as the CSS the prototype emits today."""
    out = []
    for e in t['effects']:
        if e['kind'] not in EFFECT_KINDS:
            raise ValueError('%s: unknown effect %r' % (t['id'], e['kind']))
        out.append(effect_css(e))
    return '\n'.join(out)


# ------------------------------------------------------------ theme motion
# Durations and the easing curve, as theme data.
#
# The prototype keeps these three in `css/tokens.css` as one global set:
# `--dur: 180ms`, `--dur-page: 260ms` and
# `--ease: cubic-bezier(0.2, 0.7, 0.2, 1)`. All eleven themes share them,
# because that is the design as it stands: eleven themes, one timing. They are
# theme data here so that a pack (Part C) can ship its own, and nothing in the
# prototype may change to make room.
#
# So `tokens()` does not carry them and `main()` writes nothing new: the
# `--dur`, `--dur-page` and `--ease` custom properties are defined once, in
# `tokens.css`, for every theme, and `css/themes.css` stays byte for byte what
# it is. A motion record is therefore not a CSS token, and it does not join
# `GROUP_OF` below - that classifies the custom properties written into
# `css/themes.css`, and motion is not one of them.
#
# That is also why it is a top-level key of the theme JSON beside `effects`,
# rather than a group inside `tokens`: inside `tokens` it would be a token
# with no Dart getter and no prototype rule behind it. Like effects, it is a
# record with its own Dart type (`OrbitMotion`).

# Seconds, not milliseconds: that is the CSS time unit, so the number a pack
# author writes is the number they already know, and `OrbitMotion` converts
# once, in one place, when it reads the file.
MOTION = {
    'duration': {'short': 0.18, 'page': 0.26},
    'curve': [0.2, 0.7, 0.2, 1.0],
}

# The durations a theme must carry, and what each one is in the prototype.
# Everything is classified, exactly as `GROUP_OF` does for tokens: an
# unrecognised key is an error, never a value quietly dropped on the way to
# Flutter.
MOTION_DURATIONS = {
    'short': '--dur',
    'page': '--dur-page',
}

# `cubic-bezier()` takes four control points and its own first and third, the
# x coordinates, must lie within 0..1 or the function is not a function. CSS
# rejects it and so does Flutter's `Cubic`, so it is checked here where the
# message can say which theme and which number.
MOTION_CURVE_KEY = 'curve'


def json_motion(t):
    """A theme's motion record, as the JSON the Flutter port reads.

    A theme overrides the shared `MOTION` with a `motion=` key. None of the
    eleven do, and that is deliberate: inventing a timing difference between
    themes would be a design change, and the plan approves none.
    """
    m = t.get('motion', MOTION)
    if not isinstance(m, dict):
        raise ValueError('%s: motion is not a record: %r' % (t['id'], m))

    durations = m.get('duration')
    if not isinstance(durations, dict) or set(durations) != set(MOTION_DURATIONS):
        raise ValueError('%s: motion needs a duration of exactly %s'
                         % (t['id'], ', '.join(sorted(MOTION_DURATIONS))))
    out = {}
    for name, css_name in MOTION_DURATIONS.items():
        v = durations[name]
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            raise ValueError('%s: motion duration %s (%s) is not a number of '
                             'seconds: %r'
                             % (t['id'], name, css_name, v))
        if v < 0:
            raise ValueError('%s: motion duration %s (%s) is negative: %r'
                             % (t['id'], name, css_name, v))
        out[name] = float(v)

    curve = m.get(MOTION_CURVE_KEY)
    if not isinstance(curve, (list, tuple)) or len(curve) != 4:
        raise ValueError('%s: motion curve is not a cubic-bezier: %r'
                         % (t['id'], curve))
    points = []
    for i, v in enumerate(curve):
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            raise ValueError('%s: motion curve point %d is not a number: %r'
                             % (t['id'], i, v))
        points.append(float(v))
    for i in (0, 2):
        if not 0.0 <= points[i] <= 1.0:
            raise ValueError('%s: motion curve point %d (%.3f) is outside 0..1, '
                             'so it is not a cubic-bezier'
                             % (t['id'], i, points[i]))
    return {'duration': out, MOTION_CURVE_KEY: points}


# ------------------------------------------------------------------ themes
THEMES = [
    dict(id='orbit', name='Orbit', vibe='Default', dark=False, icon='',
         bg='#F5F7FA', surface='#FFFFFF', field='#EEF1F5', ink='#131722', ink2='#394152', ink3='#636C80', ink4='#8E96A8', chat_bg='#F4F6F9',
         accent='#2563EB', accent_ink='#1D4FC4', on_accent='#FFFFFF', read='#2563EB', second='#13B4D2', second_ink='#0A6C80',
         out='#E1F7FC', out_line='#B2E7F2', out_ink='#0A2A33', out_meta='#3B6D79', inb='#FFFFFF', in_line='#E2E6ED', in_meta='#636C80',
         success='#12905A', warning='#B86E00', danger='#D23A3A',
         call=('#0B7A84', '#1D63D8', '#1A3C9E'), on_brand='#FFFFFF', call_live='#B9F6D4', wordmark=('#0EA5B7', '#2563EB', '#7C3AED'),
         hues=['#2563EB', '#0A8FA8', '#7C4DD8', '#14946F', '#B87A12', '#D04A6E', '#5E8A1A', '#5A6680'],
         font='"Geist", ui-sans-serif, system-ui, sans-serif', display='"Geist", ui-sans-serif, system-ui, sans-serif', mono='"Geist Mono", ui-monospace, monospace',
         display_weight=650, display_tracking='-0.02em', wordmark_tracking='-0.045em', transform='none',
         radii=dict(xs=6, sm=10, md=14, lg=18, xl=24, pill=999), avatar='25%', bubble=9, cut=5,
         pattern=('none', {}), glow='0 0 0 transparent', effects=(),
         over={'line': '#E2E6ED', 'line-2': '#ECEFF3', 'pressed': '#E8EBF0', 'chat-dot': '#D6DCE5', 'accent-soft': '#E8F0FE', 'accent-line': '#C4D6FB',
               'control-line': '#B8C0CD', 'switch-off': '#D3D8E1', 'media-ph': '#DCE1E8', 'map-bg': '#E8EEF3', 'map-line': '#D7DFE7',
               'wave-idle': '#C2C9D5', 'wave-out-idle': '#9FCFDA', 'danger-zone-bg': '#FFFCFC', 'danger-zone-line': '#F6DCDC',
               'success-soft': '#E3F5EC', 'warning-soft': '#FCF1DE', 'danger-soft': '#FCEAEA',
               'success-line': '#B9E4CD', 'warning-line': '#F1D9AE', 'danger-line': '#F3C9C9', 'hover': 'rgba(19, 23, 34, 0.035)',
               'tint-out': 'rgba(10, 42, 51, 0.06)', 'inverse-accent': '#9DBDFF', 'glass-accent': '#1D4FC4',
               'av-0-bg': '#E3ECFD', 'av-0-ink': '#1D4FC4', 'av-1-bg': '#DCF3F8', 'av-1-ink': '#0A6C80', 'av-2-bg': '#EEE7FB', 'av-2-ink': '#6940AE',
               'av-3-bg': '#DCF2EB', 'av-3-ink': '#116F59', 'av-4-bg': '#FAEEDA', 'av-4-ink': '#87580A', 'av-5-bg': '#FBE5EA', 'av-5-ink': '#A23355',
               'av-6-bg': '#E9F4D8', 'av-6-ink': '#4B6912', 'av-7-bg': '#E6EAF0', 'av-7-ink': '#3E4A5D'}),

    dict(id='night', name='Orbit Night', vibe='Default · dark', dark=True, icon='',
         bg='#0D1117', surface='#161B24', field='#1F2532', ink='#E6EAF2', ink2='#C3C9D6', ink3='#9AA3B5', ink4='#6B7387', chat_bg='#0F141C',
         accent='#5B8CFF', accent_ink='#93B3FF', on_accent='#0B1020', read='#7AA2FF', second='#4FD1E8', second_ink='#86E3F3',
         out='#123A47', out_line='#1F5363', out_ink='#DDF7FD', out_meta='#93CFDC', inb='#1C2331', in_line='#283143', in_meta='#A2ABBD',
         success='#3DD68C', warning='#F2B544', danger='#FF6B6B',
         call=('#0A5C66', '#1A4FB8', '#142B6B'), on_brand='#FFFFFF', call_live='#B9F6D4', wordmark=('#2BC4D6', '#6E97FF', '#A884FF'),
         hues=['#5B8CFF', '#2BC4D6', '#A884FF', '#34C6A0', '#F2B544', '#FF7A9A', '#9BD35A', '#9AA8C0'],
         font='"Geist", ui-sans-serif, system-ui, sans-serif', display='"Geist", ui-sans-serif, system-ui, sans-serif', mono='"Geist Mono", ui-monospace, monospace',
         display_weight=650, display_tracking='-0.02em', wordmark_tracking='-0.045em', transform='none',
         radii=dict(xs=6, sm=10, md=14, lg=18, xl=24, pill=999), avatar='25%', bubble=9, cut=5,
         pattern=('none', {}), glow='0 0 0 transparent', effects=()),

    dict(id='bloom', name='Bloom', vibe='Aesthetic', dark=False, icon='light',
         bg='#F7F1EC', surface='#FFFDFB', field='#F1E7E0', ink='#3B2F2F', ink2='#574542', ink3='#75605B', ink4='#A8958F', chat_bg='#F4ECE6',
         accent='#9E5F55', accent_ink='#874E45', on_accent='#FFFFFF', read='#5E7E61', second='#6F8F72', second_ink='#4C6A50',
         out='#EADBD3', out_line='#DCC4B8', out_ink='#3B2F2F', out_meta='#6E5048', inb='#FFFDFB', in_line='#EBDDD4', in_meta='#75605B',
         success='#3F7A4C', warning='#9A5A12', danger='#A83A30',
         call=('#9E5F55', '#7D5F86', '#4F6B5E'), on_brand='#FFFFFF', call_live='#F3E1D6', wordmark=('#9E5F55', '#C08A6E', '#6F8F72'),
         hues=['#9E5F55', '#6F8F72', '#8E6BA8', '#C08A6E', '#A8742E', '#C2667A', '#7A8F4F', '#8A7F79'],
         font='"DM Sans", ui-sans-serif, system-ui, sans-serif', display='"Fraunces", Georgia, serif', mono='"DM Mono", ui-monospace, monospace',
         display_weight=560, display_tracking='-0.01em', wordmark_tracking='-0.02em', transform='none',
         radii=dict(xs=8, sm=12, md=16, lg=22, xl=28, pill=999), avatar='50%', bubble=18, cut=6,
         pattern=('grain', dict(r=0.55, g=0.35, b=0.3, a=0.06, size=(160, 160))), glow='0 0 0 transparent',
         effects=(
    {'kind': 'wordmarkItalic', 'theme': 'bloom', 'params': {}},
             {'kind': 'dayLabel', 'theme': 'bloom', 'params': dict(size='13px')},
         ),),

    dict(id='mochi', name='Mochi', vibe='Cute', dark=False, icon='duotone',
         bg='#FFF4F9', surface='#FFFFFF', field='#FFE9F3', ink='#4A3550', ink2='#5E4766', ink3='#755F7E', ink4='#B39DBA', chat_bg='#FFF7FB',
         accent='#CC3D82', accent_ink='#B02E6C', on_accent='#FFFFFF', read='#B02E6C', second='#9B7BFF', second_ink='#6447D6',
         out='#FFDCEC', out_line='#FFC2DD', out_ink='#5A2A45', out_meta='#86466A', inb='#F1E9FF', in_line='#E4D8FF', in_meta='#66507F',
         success='#21875C', warning='#A35F00', danger='#C42E4F',
         call=('#C93A80', '#9A57DC', '#6A4FD6'), on_brand='#FFFFFF', call_live='#FFE3F0', wordmark=('#FF6FAE', '#B98CFF', '#6FC8FF'),
         hues=['#FF6FAE', '#4DB8F0', '#B98CFF', '#3DC79A', '#FFA44D', '#FF7A7A', '#8CCB4E', '#C9A8E8'],
         font='"Nunito", ui-rounded, system-ui, sans-serif', display='"Nunito", ui-rounded, system-ui, sans-serif', mono='"Nunito", ui-rounded, system-ui, sans-serif',
         display_weight=800, display_tracking='-0.01em', wordmark_tracking='-0.02em', transform='none',
         radii=dict(xs=10, sm=14, md=18, lg=24, xl=30, pill=999), avatar='50%', bubble=22, cut=22,
         pattern=('hearts', dict(size=(64, 64))), glow='0 0 0 transparent',
         effects=(
    {'kind': 'ornament', 'theme': 'mochi', 'params': dict(
                 target='wordmark', pseudo='after', glyph=' ♡', fill=True,
                 colour=lit('#FF8FC0'), size='0.62em')},
             {'kind': 'bubbleWeight', 'theme': 'mochi', 'params': dict(weight=600)},
             {'kind': 'dockBorder', 'theme': 'mochi', 'params': dict(
                 width=2, colour=lit('#FFD1E6'))},
             {'kind': 'ornament', 'theme': 'mochi', 'params': dict(
                 target='day', pseudo='before', glyph='✦ ', colour=lit('#FF8FC0'))},
         ),),

    dict(id='papyrus', name='Papyrus', vibe='Ancient', dark=False, icon='light',
         bg='#F2E8D5', surface='#FBF5E9', field='#EADFC8', ink='#3E2C1C', ink2='#54402B', ink3='#6A5640', ink4='#9C8A70', chat_bg='#EFE3CB',
         accent='#8A5A12', accent_ink='#734A0B', on_accent='#FBF5E9', read='#7A3B2E', second='#7A3B2E', second_ink='#6A2F23',
         out='#E6CFA0', out_line='#CDB27A', out_ink='#3E2C1C', out_meta='#5E421A', inb='#FBF5E9', in_line='#D9C49B', in_meta='#6A5640',
         success='#45622A', warning='#8F5300', danger='#9B2C1F',
         call=('#8A5A12', '#6B4423', '#3E2C1C'), on_brand='#FBF5E9', call_live='#F1DDB0', wordmark=('#8A5A12', '#B8862B', '#5C3A12'),
         hues=['#8A5A12', '#7A3B2E', '#4E6B2E', '#5C4A7A', '#9C6B2E', '#8C3F55', '#6B6B2E', '#6E5A44'],
         font='"EB Garamond", Garamond, Georgia, serif', display='"Cinzel", "Trajan Pro", Georgia, serif', mono='"EB Garamond", Garamond, Georgia, serif',
         display_weight=600, display_tracking='0.05em', wordmark_tracking='0.08em', transform='none',
         radii=dict(xs=2, sm=3, md=4, lg=6, xl=8, pill=4), avatar='8%', bubble=4, cut=1,
         pattern=('grain', dict(r=0.24, g=0.17, b=0.1, a=0.10, size=(160, 160))), glow='0 0 0 transparent',
         effects=(
    {'kind': 'pagePattern', 'theme': 'papyrus', 'params': {}},
             {'kind': 'baseFontSize', 'theme': 'papyrus', 'params': dict(size='16px')},
             {'kind': 'ornament', 'theme': 'papyrus', 'params': dict(
                 target='day', pseudo='before', glyph='❦ ')},
             {'kind': 'ornament', 'theme': 'papyrus', 'params': dict(
                 target='day', pseudo='after', glyph=' ❦')},
             {'kind': 'cardRing', 'theme': 'papyrus', 'params': dict(
                 targets=['.card', '.hero-card'],
                 rings=[dict(width=3, token='surface'),
                        dict(width=4, token='line')])},
         ),),

    dict(id='arcade', name='Arcade', vibe='Gaming · neon', dark=True, icon='bold',
         bg='#0B0A14', surface='#141228', field='#1F1C3A', ink='#EDEBFF', ink2='#CFCBEF', ink3='#A7A3C9', ink4='#6E6A92', chat_bg='#0D0B1A',
         accent='#00E5FF', accent_ink='#5CF0FF', on_accent='#05060D', read='#00E5FF', second='#FF2E88', second_ink='#FF7AB6',
         out='#2A0F3D', out_line='#FF2E88', out_ink='#FFE3F1', out_meta='#FF9CCB', inb='#12233A', in_line='#00B8D9', in_meta='#8FD9E8',
         success='#39FF88', warning='#FFD600', danger='#FF4D6D',
         call=('#A8125F', '#5B1FD1', '#006B87'), on_brand='#FFFFFF', call_live='#39FF88', wordmark=('#00E5FF', '#7A5CFF', '#FF2E88'),
         hues=['#00E5FF', '#FF2E88', '#7A5CFF', '#39FF88', '#FFD600', '#FF8A3D', '#B6FF3D', '#8F8FBF'],
         font='"Exo 2", ui-sans-serif, system-ui, sans-serif', display='"Rajdhani", "Exo 2", sans-serif', mono='"Share Tech Mono", ui-monospace, monospace',
         display_weight=700, display_tracking='0.04em', wordmark_tracking='0.06em', transform='uppercase',
         radii=dict(xs=2, sm=4, md=6, lg=8, xl=10, pill=6), avatar='12%', bubble=6, cut=0,
         pattern=('neonGrid', dict(h='#FF2E88', ha=0.07, v='#00E5FF', va=0.06, size=(28, 28))),
         glow='0 0 18px rgba(0, 229, 255, 0.45)',
         effects=(
    {'kind': 'bubbleGlow', 'theme': 'arcade', 'params': {
                 'in': dict(dx=0, dy=0, blur=14, colour=lit('#00E5FF', 0.16)),
                 'out': dict(dx=0, dy=0, blur=14, colour=lit('#FF2E88', 0.24))}},
             {'kind': 'wordmarkGlow', 'theme': 'arcade', 'params': dict(
                 dx=0, dy=0, blur=10, colour=lit('#7A5CFF', 0.6))},
             {'kind': 'cornerClip', 'theme': 'arcade', 'params': dict(
                 notch=10, radius='0', shadow='none',
                 targets=['.btn.primary', '.xfab'])},
             {'kind': 'eyebrowColour', 'theme': 'arcade', 'params': dict(
                 targets=['.eyebrow', '.day span'], token='accent-ink')},
         ),),

    dict(id='terminal', name='Terminal', vibe='Tech', dark=True, icon='light',
         bg='#050805', surface='#0B120C', field='#121D13', ink='#C8F7C5', ink2='#A8E6A5', ink3='#86BC85', ink4='#4E7A4D', chat_bg='#060A06',
         accent='#39FF88', accent_ink='#6BFFA6', on_accent='#031006', read='#39FF88', second='#FFB000', second_ink='#FFC94D',
         out='#0F2A17', out_line='#39FF88', out_ink='#D7FFD9', out_meta='#86DB99', inb='#0D160E', in_line='#23402A', in_meta='#86BC85',
         success='#39FF88', warning='#FFB000', danger='#FF5F56',
         call=('#11472A', '#0B3019', '#04140A'), on_brand='#D7FFD9', call_live='#39FF88', wordmark=('#39FF88', '#00E0A0', '#39FF88'),
         hues=['#39FF88', '#00E0A0', '#FFB000', '#5CD6FF', '#B6FF3D', '#FF5F56', '#C8F7C5', '#7FB27E'],
         font='"JetBrains Mono", ui-monospace, monospace', display='"JetBrains Mono", ui-monospace, monospace', mono='"JetBrains Mono", ui-monospace, monospace',
         display_weight=700, display_tracking='0', wordmark_tracking='-0.02em', transform='none',
         radii=dict(xs=2, sm=2, md=2, lg=2, xl=4, pill=2), avatar='4%', bubble=2, cut=0,
         pattern=('scanlines', dict(colour='#39FF88', a=0.045, thickness=1, period=3)),
         glow='0 0 14px rgba(57, 255, 136, 0.35)',
         effects=(
    {'kind': 'wordmarkGlow', 'theme': 'terminal', 'params': dict(
                 dx=0, dy=0, blur=8, colour=lit('#39FF88', 0.45))},
             {'kind': 'cursor', 'theme': 'terminal', 'params': dict(
                 glyph='_', colour=tok('accent'), period='1s')},
             {'kind': 'ornament', 'theme': 'terminal', 'params': dict(
                 target='day', pseudo='before', glyph='[ ')},
             {'kind': 'ornament', 'theme': 'terminal', 'params': dict(
                 target='day', pseudo='after', glyph=' ]')},
             {'kind': 'ornament', 'theme': 'terminal', 'params': dict(
                 target='group', pseudo='before', glyph='# ')},
         ),),

    dict(id='field', name='Field', vibe='Army', dark=True, icon='bold',
         bg='#1C2118', surface='#252C1F', field='#2F3727', ink='#E4E0CC', ink2='#CFCAB2', ink3='#B0AB93', ink4='#7D7A66', chat_bg='#1A1F16',
         accent='#C9B77A', accent_ink='#D9C994', on_accent='#1C2118', read='#D9C994', second='#D9822B', second_ink='#E79A4A',
         out='#3A4428', out_line='#56633A', out_ink='#F0ECD6', out_meta='#C4BF9C', inb='#2A3122', in_line='#3A4430', in_meta='#B0AB93',
         success='#9CCB66', warning='#E8A93C', danger='#F06A5A',
         call=('#4B5320', '#3A4128', '#262B1C'), on_brand='#F0ECD6', call_live='#C9E08A', wordmark=('#E4D9A8', '#C9B77A', '#8A9A5B'),
         hues=['#C9B77A', '#8A9A5B', '#D9822B', '#6F8F9A', '#B0A070', '#C06A50', '#9AB060', '#8A8570'],
         font='"Barlow", ui-sans-serif, system-ui, sans-serif', display='"Black Ops One", "Barlow", sans-serif', mono='"JetBrains Mono", ui-monospace, monospace',
         display_weight=400, display_tracking='0.04em', wordmark_tracking='0.05em', transform='uppercase',
         radii=dict(xs=2, sm=3, md=4, lg=4, xl=6, pill=3), avatar='6%', bubble=3, cut=0,
         pattern=('contours', dict(stroke='#323B29', width=1.3, size=(220, 220))), glow='0 0 0 transparent',
         effects=(
    {'kind': 'bubbleStripe', 'theme': 'field', 'params': {
                 'in': dict(edge='left', width=3, colour=lit('#6B7A45')),
                 'out': dict(edge='right', width=3, colour=tok('accent'))}},
             {'kind': 'ornament', 'theme': 'field', 'params': dict(
                 target='group', pseudo='before', glyph='▸ ', colour=tok('accent'))},
         ),),

    dict(id='jungle', name='Jungle', vibe='Botanical', dark=False, icon='duotone',
         bg='#EAF1E6', surface='#F8FBF4', field='#DFEAD8', ink='#132A18', ink2='#2F4A34', ink3='#4C6A52', ink4='#86A08A', chat_bg='#E4EEDF',
         accent='#1E7B44', accent_ink='#155C32', on_accent='#FFFFFF', read='#1B6B3B', second='#B4560F', second_ink='#8A400A',
         out='#D3E9C6', out_line='#B7D9A6', out_ink='#132A18', out_meta='#4C6A52', inb='#FBFDF8', in_line='#D9E6D3', in_meta='#4C6A52',
         success='#0F6B39', warning='#96601A', danger='#B03A2E',
         call=('#14532D', '#0E7A4B', '#093D24'), on_brand='#FFFFFF', call_live='#BBF0CC', wordmark=('#1E7B44', '#B4560F', '#0E7A4B'),
         hues=['#1E7B44', '#B4560F', '#0E7490', '#7A6B12', '#9A3F6E', '#3F6E8A', '#6B4A8A', '#5E6E52'],
         font='"DM Sans", ui-sans-serif, system-ui, sans-serif', display='"Fraunces", Georgia, serif', mono='"DM Mono", ui-monospace, monospace',
         display_weight=560, display_tracking='-0.01em', wordmark_tracking='-0.02em', transform='none',
         radii=dict(xs=8, sm=12, md=16, lg=20, xl=26, pill=999), avatar='30%', bubble=16, cut=6,
         pattern=('grain', dict(r=0.1, g=0.24, b=0.13, a=0.07, size=(160, 160))), glow='0 0 0 transparent',
         effects=()),

    dict(id='ocean', name='Ocean', vibe='Deep sea', dark=True, icon='light',
         bg='#0A1A22', surface='#112A34', field='#183A46', ink='#E2F2F7', ink2='#BEDAE4', ink3='#8FBAC8', ink4='#5E8C9C', chat_bg='#0D2028',
         accent='#2EB8C9', accent_ink='#6FD3E8', on_accent='#04222A', read='#7FDCF0', second='#F2A65A', second_ink='#FFD1A3',
         out='#0F3D4A', out_line='#1B5A6B', out_ink='#D9F2F8', out_meta='#8FC4D4', inb='#16313C', in_line='#235061', in_meta='#9CC3D2',
         success='#3DD68C', warning='#F2B544', danger='#FF6B6B',
         call=('#0B4A5A', '#0A3A6B', '#072840'), on_brand='#EAF7FB', call_live='#7CE0B6', wordmark=('#2EB8C9', '#6FD3E8', '#F2A65A'),
         hues=['#2EB8C9', '#F2A65A', '#7C8FE8', '#3DD68C', '#E86F9A', '#8FD14F', '#5AD1C0', '#9BB4C4'],
         font='"Barlow", ui-sans-serif, system-ui, sans-serif', display='"Rajdhani", "Barlow", sans-serif', mono='"JetBrains Mono", ui-monospace, monospace',
         display_weight=700, display_tracking='0.04em', wordmark_tracking='0.02em', transform='uppercase',
         radii=dict(xs=8, sm=12, md=16, lg=20, xl=26, pill=999), avatar='50%', bubble=14, cut=8,
         pattern=('contours', dict(stroke='#1B5A6B', width=1.4, size=(220, 220))), glow='0 0 16px rgba(46, 184, 201, 0.28)',
         effects=(
    {'kind': 'wordmarkGlow', 'theme': 'ocean', 'params': dict(
                 dx=0, dy=0, blur=10, colour=lit('#2EB8C9', 0.35))},
         ),),

    dict(id='metal', name='Metal', vibe='Industrial', dark=True, icon='bold',
         bg='#1A1C1F', surface='#26292E', field='#31353C', ink='#E8EAEE', ink2='#C6CBD2', ink3='#9EA5AE', ink4='#6E757F', chat_bg='#191B1E',
         accent='#BAC4CF', accent_ink='#DCE3EA', on_accent='#1A1C1F', read='#9FC6E8', second='#C9A227', second_ink='#E3C455',
         out='#3A3F46', out_line='#565C65', out_ink='#EDF0F4', out_meta='#B9C0C9', inb='#2E3238', in_line='#444A52', in_meta='#B4BAC2',
         success='#5BD98A', warning='#E8B33C', danger='#FF6A55',
         call=('#3A4048', '#22262C', '#4A5058'), on_brand='#EEF1F5', call_live='#B9F6D4', wordmark=('#D7DEE6', '#9AA6B4', '#C9A227'),
         hues=['#BAC4CF', '#8FA9C4', '#C9A227', '#7FB8A0', '#C98A8A', '#A28FC4', '#9FB07F', '#8A9AA8'],
         font='"Exo 2", ui-sans-serif, system-ui, sans-serif', display='"Exo 2", ui-sans-serif, system-ui, sans-serif', mono='"Share Tech Mono", ui-monospace, monospace',
         display_weight=700, display_tracking='0.06em', wordmark_tracking='0.04em', transform='uppercase',
         radii=dict(xs=3, sm=5, md=7, lg=9, xl=12, pill=5), avatar='15%', bubble=6, cut=3,
         pattern=('scanlines', dict(colour='#DDE3EA', a=0.03, thickness=1, period=4)),
         glow='0 0 12px rgba(200, 212, 226, 0.20)',
         effects=(
    {'kind': 'cornerClip', 'theme': 'metal', 'params': dict(
                 notch=7, radius='2px', shadow='none',
                 targets=['.btn.primary', '.xfab'])},
             {'kind': 'eyebrowColour', 'theme': 'metal', 'params': dict(
                 targets=['.eyebrow', '.day span'], token='accent-ink')},
         ),),
]


def tokens(t):
    d = t['dark']
    s, ink, acc = t['surface'], t['ink'], t['accent']
    k = {
        'bg': t['bg'], 'surface': s, 'field': t['field'], 'pressed': mix(s, ink, 0.08),
        'ink': ink, 'ink-2': t['ink2'], 'ink-3': t['ink3'], 'ink-4': t['ink4'],
        'line': mix(s, ink, 0.12 if not d else 0.14), 'line-2': mix(s, ink, 0.07 if not d else 0.09),
        'chat-bg': t['chat_bg'], 'chat-dot': mix(t['chat_bg'], ink, 0.13),
        'scrim': 'rgba(0, 0, 0, 0.55)' if d else 'rgba(13, 16, 25, 0.42)',
        'accent': acc, 'accent-ink': t['accent_ink'], 'accent-soft': mix(s, acc, 0.18 if d else 0.12),
        'accent-line': mix(s, acc, 0.4 if d else 0.3), 'on-accent': t['on_accent'], 'read': t['read'],
        'cyan': t['second'], 'cyan-ink': t['second_ink'] if contrast(t['second_ink'], t['out']) >= 4.6 else fit_ink(t['second_ink'], t['out'], d),
        'out': t['out'], 'out-line': t['out_line'], 'out-ink': t['out_ink'], 'out-meta': t['out_meta'],
        'in': t['inb'], 'in-line': t['in_line'], 'in-ink': ink, 'in-meta': t['in_meta'],
        **status('success', t['success'], s, d), **status('warning', t['warning'], s, d), **status('danger', t['danger'], s, d),
        'inverse': ink, 'on-inverse': t['bg'], 'inverse-accent': fit_ink(acc, ink, not d),
        'hover': rgba(ink, 0.05 if d else 0.035), 'dock-bg': rgba(s, 0.96), 'notice-bg': rgba(s, 0.88),
        'tint': rgba(ink, 0.07 if d else 0.04), 'tint-out': rgba(t['out_ink'], 0.08 if d else 0.06),
        'media-ph': mix(s, ink, 0.14), 'map-bg': mix(s, acc, 0.08), 'map-line': mix(s, ink, 0.14),
        'wave-idle': mix(t['inb'], t['in_meta'], 0.45), 'wave-out-idle': mix(t['out'], t['out_meta'], 0.45),
        'mark': 'rgba(255, 214, 0, 0.38)' if d else '#FFE58F',
        'switch-off': mix(s, ink, 0.25), 'switch-knob': '#FFFFFF' if not d else mix(s, ink, 0.92),
        'control-line': mix(s, ink, 0.32), 'danger-zone-bg': mix(s, t['danger'], 0.04), 'danger-zone-line': mix(s, t['danger'], 0.16),
        'gesture': rgba(ink, 0.4 if d else 0.32), 'pressed': mix(s, ink, 0.08),
        'on-brand': t['on_brand'], 'glass-bg': rgba(s, 0.92) if d else 'rgba(255, 255, 255, 0.92)', 'glass-ink': ink, 'glass-accent': t['accent_ink'],
        'call-top': fit_bg(t['call'][0], t['on_brand']), 'call-mid': fit_bg(t['call'][1], t['on_brand'], 5.4), 'call-bottom': fit_bg(t['call'][2], t['on_brand']), 'call-text': t['on_brand'],
        'call-muted': rgba(t['on_brand'], 0.9), 'call-glass': rgba(t['on_brand'], 0.14), 'call-glass-2': rgba(t['on_brand'], 0.22),
        'call-line': rgba(t['on_brand'], 0.26), 'call-live': t['call_live'],
        'brand-gradient': 'linear-gradient(150deg, var(--call-top) 0%, var(--call-mid) 55%, var(--call-bottom) 100%)',
        'wordmark-gradient': f"linear-gradient(100deg, {t['wordmark'][0]} 0%, {t['wordmark'][1]} 48%, {t['wordmark'][2]} 100%)",
        'wordmark-tracking': t['wordmark_tracking'],
        'chat-pattern': pattern_css(t['pattern']),
        'chat-pattern-size': pattern_size_css(t['pattern']), 'glow': t['glow'],
        'font': t['font'], 'font-display': t['display'], 'mono': t['mono'],
        'display-weight': str(t['display_weight']), 'display-tracking': t['display_tracking'], 'display-transform': t['transform'],
        'avatar-r': t['avatar'], 'bubble-r': f"{t['bubble']}px", 'bubble-cut': f"{t['cut']}px",
        'shadow-card': '0 1px 2px rgba(0, 0, 0, 0.35)' if d else '0 1px 2px rgba(19, 23, 34, 0.04)',
        'shadow-float': '0 14px 34px -10px rgba(0, 0, 0, 0.65), 0 2px 6px rgba(0, 0, 0, 0.35)' if d else '0 14px 34px -10px rgba(19, 23, 34, 0.22), 0 2px 6px rgba(19, 23, 34, 0.06)',
        'shadow-sheet': '0 -10px 40px rgba(0, 0, 0, 0.55)' if d else '0 -10px 40px rgba(19, 23, 34, 0.14)',
    }
    # Status text is re-fitted against the final soft tint below if a theme pins its own tint.
    k.update(t.get('over', {}))
    for st in ('success', 'warning', 'danger'):
        if contrast(k[st], k[f'{st}-soft']) < 4.6:
            k[st] = fit_ink(k[st], k[f'{st}-soft'], d)
    for name, px in t['radii'].items():
        k[f'r-{name}'] = f'{px}px'
    for i, hue in enumerate(t['hues']):
        if f'av-{i}-bg' in t.get('over', {}):
            continue
        bgc = mix(s, hue, 0.22 if d else 0.16)
        k[f'av-{i}-bg'] = bgc
        k[f'av-{i}-ink'] = fit_ink(hue, bgc, d)
    return k


# --------------------------------------------------------------- theme JSON
# One JSON file per theme, for the Flutter port (Phase 2) and for a downloaded
# theme pack (Part C). It is TYPED: colours arrive as a colour, a radius as a
# number, a shadow as offsets and a colour. Flutter must not parse CSS, and a
# pack that carried CSS syntax would be data the app cannot use.
#
# The values come from the same `tokens()` map that writes the CSS, so the two
# cannot disagree. Every key must be classified below; anything unclassified is
# an error, never a silently dropped token. The two records that are *not*
# custom properties - `effects` and `motion` - sit beside `tokens` for that
# reason: they have their own Dart types and no CSS rule behind them.

COLOUR_KEYS = """
bg surface field pressed ink ink-2 ink-3 ink-4 line line-2 chat-bg chat-dot
scrim accent accent-ink accent-soft accent-line on-accent read cyan cyan-ink
out out-line out-ink out-meta in in-line in-ink in-meta
success success-soft success-line warning warning-soft warning-line
danger danger-soft danger-line
inverse on-inverse inverse-accent hover dock-bg notice-bg tint tint-out
glass-bg glass-ink glass-accent on-brand
media-ph map-bg map-line wave-idle wave-out-idle mark switch-off switch-knob
control-line danger-zone-bg danger-zone-line gesture
call-top call-mid call-bottom call-text call-muted call-glass call-glass-2
call-line call-live
""".split()

AVATAR_KEYS = ['av-%d-%s' % (i, part) for i in range(8) for part in ('bg', 'ink')]

SHADOW_KEYS = {'shadow-card', 'shadow-float', 'shadow-sheet', 'glow'}
GRADIENT_KEYS = {'wordmark-gradient'}
# A gradient over other tokens rather than over colours of its own. Flutter
# builds it from the call colours, so only the order and the stops are data.
GRADIENT_REF_KEYS = {'brand-gradient'}
FONT_KEYS = {'font', 'font-display', 'mono'}
WEIGHT_KEYS = {'display-weight'}
EM_KEYS = {'wordmark-tracking', 'display-tracking'}
TRANSFORM_KEYS = {'display-transform'}
PATTERN_KEYS = {'chat-pattern'}
PATTERN_SIZE_KEYS = {'chat-pattern-size'}
PX_KEYS = {'bubble-r', 'bubble-cut'} | {'r-%s' % n
                                       for n in ('xs', 'sm', 'md', 'lg', 'xl', 'pill')}
PCT_KEYS = {'avatar-r'}

KINDS = ([('colour', COLOUR_KEYS + AVATAR_KEYS),
          ('shadow', SHADOW_KEYS),
          ('gradient', GRADIENT_KEYS),
          ('gradientRef', GRADIENT_REF_KEYS),
          ('fontStack', FONT_KEYS),
          ('weight', WEIGHT_KEYS),
          ('em', EM_KEYS),
          ('transform', TRANSFORM_KEYS),
          ('pattern', PATTERN_KEYS),
          ('patternSize', PATTERN_SIZE_KEYS),
          ('lengthPx', PX_KEYS),
          ('lengthPct', PCT_KEYS)])

GROUP_OF = {}
for _kind, _keys in KINDS:
    for _key in _keys:
        if _key in GROUP_OF:
            raise SystemExit('%s is claimed by two groups (%s)'
                             % (_key, GROUP_OF[_key]))
        GROUP_OF[_key] = _kind


def split_top(s, sep=','):
    """Split on `sep`, ignoring any inside brackets: `rgba(1, 2, 3, .4)` is one."""
    parts, depth, cur = [], 0, ''
    for ch in s:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        if ch == sep and depth == 0:
            parts.append(cur)
            cur = ''
        else:
            cur += ch
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]


def json_colour(v):
    """`#RRGGBB` or `rgba(r, g, b, a)` -> `{"hex": ..., "alpha": ...}`."""
    v = v.strip()
    if v.lower() == 'transparent':
        return {'hex': '#000000', 'alpha': 0}
    if v.startswith('#'):
        return {'hex': v.upper(), 'alpha': 1}
    if not (v.startswith('rgb(') or v.startswith('rgba(')):
        raise ValueError('not a colour: %r' % v)
    parts = split_top(v[v.index('(') + 1:v.rindex(')')])
    if len(parts) == 3:
        parts = parts + ['1']
    if len(parts) != 4:
        raise ValueError('not a colour: %r' % v)
    r, g, b = (int(float(p)) for p in parts[:3])
    return {'hex': hexc((r, g, b)), 'alpha': float(parts[3])}


def json_shadow(v):
    """A CSS `box-shadow` value -> a list of `{dx, dy, blur, spread, colour}`.

    `glow` is the same shape: it is a box-shadow the themes pass to their
    buttons, and `0 0 0 transparent` is a glow of nothing.
    """
    out = []
    for layer in split_top(v):
        words = layer.split()
        nums = []
        while words and len(nums) < 4:
            m = re.fullmatch(r'(-?[\d.]+)(?:px)?', words[0])
            if not m:
                break
            nums.append(float(m.group(1)))
            words = words[1:]
        if not 2 <= len(nums) <= 4:
            raise ValueError('not a shadow: %r' % layer)
        nums += [0.0] * (4 - len(nums))
        colour = ' '.join(words) if words else 'transparent'
        out.append({'dx': nums[0], 'dy': nums[1], 'blur': nums[2],
                    'spread': nums[3], 'colour': json_colour(colour)})
    return out


def json_gradient(v):
    """`linear-gradient(100deg, #AAA 0%, #BBB 48%, #CCC 100%)`."""
    body = v[v.index('(') + 1:v.rindex(')')]
    parts = split_top(body)
    angle = 180.0
    if parts and parts[0].strip().endswith('deg'):
        angle = float(parts[0].strip()[:-3])
        parts = parts[1:]
    stops = []
    for part in parts:
        words = part.split()
        at = 0.0 if len(words) == 1 else float(words[1].rstrip('%')) / 100
        stops.append({'colour': json_colour(words[0]), 'at': at})
    return {'angle': angle, 'stops': stops}


def json_gradient_ref(v):
    """`linear-gradient(150deg, var(--call-top) 0%, ... )`: tokens, not colours."""
    body = v[v.index('(') + 1:v.rindex(')')]
    parts = split_top(body)
    angle = 180.0
    if parts and parts[0].strip().endswith('deg'):
        angle = float(parts[0].strip()[:-3])
        parts = parts[1:]
    stops = []
    for part in parts:
        words = part.split()
        token = words[0].strip('var()').lstrip('-')
        at = 0.0 if len(words) == 1 else float(words[1].rstrip('%')) / 100
        stops.append({'token': token, 'at': at})
    return {'angle': angle, 'stops': stops}


def json_font_stack(v):
    return {'families': [f.strip().strip('"\'') for f in split_top(v)]}


def json_length(v):
    m = re.fullmatch(r'(-?[\d.]+)px', v.strip())
    if not m:
        raise ValueError('not a pixel length: %r' % v)
    return float(m.group(1))


def json_percent(v):
    m = re.fullmatch(r'(-?[\d.]+)%', v.strip())
    if not m:
        raise ValueError('not a percentage: %r' % v)
    return float(m.group(1))


def json_em(v):
    v = v.strip()
    # CSS allows a bare zero for tracking; nothing else needs one.
    if v == '0':
        return 0
    m = re.fullmatch(r'(-?[\d.]+)em', v)
    if not m:
        raise ValueError('not an em value: %r' % v)
    return float(m.group(1))


CONVERTERS = {
    'colour': json_colour,
    'shadow': json_shadow,
    'gradient': json_gradient,
    'gradientRef': json_gradient_ref,
    'fontStack': json_font_stack,
    'weight': lambda v: int(v),
    'em': json_em,
    'transform': lambda v: v,
    'pattern': lambda v: {'kind': v[0], 'params': dict(v[1])},
    'patternSize': lambda v: ({'auto': True} if v[0] == 'none'
                              else {'w': v[1]['size'][0], 'h': v[1]['size'][1]}),
    'lengthPx': json_length,
    'lengthPct': json_percent,
}

# `pattern` and `patternSize` are read from the record, not from the CSS, so a
# theme JSON carries the name and the numbers rather than the finished value.
FROM_RECORD = {'pattern', 'patternSize'}


def theme_effects(t):
    """The effect records, minus the theme they belong to (the file knows)."""
    for e in t['effects']:
        if e['kind'] not in EFFECT_KINDS:
            raise ValueError('%s: unknown effect %r' % (t['id'], e['kind']))
    return [{'kind': e['kind'], 'params': e['params']} for e in t['effects']]


def theme_json(t, k):
    """The one file `orbit_ui` loads for this theme, and a pack's format."""
    unknown = sorted(set(k) - set(GROUP_OF))
    if unknown:
        raise SystemExit('%s: these tokens are not classified, so the Flutter '
                         'port would never see them: %s' % (t['id'], unknown))
    groups = {}
    for key, value in k.items():
        kind = GROUP_OF[key]
        if kind == 'pattern':
            groups.setdefault(kind, {})[key] = {'kind': t['pattern'][0],
                                                'params': dict(t['pattern'][1])}
        elif kind == 'patternSize':
            size = t['pattern'][1].get('size')
            groups.setdefault(kind, {})[key] = ({'auto': True} if size is None
                                                else {'w': size[0], 'h': size[1]})
        else:
            groups.setdefault(kind, {})[key] = CONVERTERS[kind](value)
    stale = sorted(set(GROUP_OF) - set(k))
    if stale:
        raise SystemExit('%s: these tokens are classified but no longer '
                         'produced: %s' % (t['id'], stale))
    # `motion` sits beside `tokens` and `effects`, not inside `tokens`: it
    # carries no custom property, so `GROUP_OF` has nothing to classify and
    # adding it there would put a `--motion` rule into a frozen file.
    return {
        'id': t['id'],
        'name': t['name'],
        'vibe': t['vibe'],
        'dark': t['dark'],
        'icon': t['icon'],
        'swatches': [t['bg'], t['accent'], t['out'], t['second']],
        'tokens': {kind: groups[kind] for kind, _ in KINDS if kind in groups},
        'motion': json_motion(t),
        'effects': theme_effects(t),
    }


# ------------------------------------------------------------ contrast check
def check(t, k):
    def over(color_rgba, base):
        parts = color_rgba[5:-1].split(',')
        r, g, b, a = [float(p) for p in parts]
        return mix(base, hexc((r, g, b)), a)
    pairs = [
        ('ink / surface', k['ink'], k['surface'], 7), ('ink-2 / surface', k['ink-2'], k['surface'], 4.5),
        ('ink-3 / surface', k['ink-3'], k['surface'], 4.5), ('ink-3 / bg', k['ink-3'], k['bg'], 4.5),
        ('ink / chat-bg', k['ink'], k['chat-bg'], 7),
        ('in-ink / in', k['in-ink'], k['in'], 7), ('in-meta / in', k['in-meta'], k['in'], 4.5),
        ('out-ink / out', k['out-ink'], k['out'], 7), ('out-meta / out', k['out-meta'], k['out'], 4.5),
        ('read / out', k['read'], k['out'], 3), ('on-accent / accent', k['on-accent'], k['accent'], 4.5),
        ('accent-ink / surface', k['accent-ink'], k['surface'], 4.5), ('accent-ink / accent-soft', k['accent-ink'], k['accent-soft'], 4.5),
        ('on-inverse / inverse', k['on-inverse'], k['inverse'], 4.5), ('inverse-accent / inverse', k['inverse-accent'], k['inverse'], 4.5),
        ('on-brand / call-top', k['on-brand'], k['call-top'], 4.5), ('on-brand / call-mid', k['on-brand'], k['call-mid'], 4.5),
        ('on-brand / call-bottom', k['on-brand'], k['call-bottom'], 4.5),
        ('call-muted / call-mid', over(k['call-muted'], k['call-mid']), k['call-mid'], 4.5),
        ('glass-accent / glass', k['glass-accent'], over(k['glass-bg'], k['call-mid']), 4.5),
        ('danger / surface', k['danger'], k['surface'], 4.5), ('danger / danger-soft', k['danger'], k['danger-soft'], 4.5),
        ('success / success-soft', k['success'], k['success-soft'], 4.5), ('warning / warning-soft', k['warning'], k['warning-soft'], 4.5),
        ('cyan-ink / out', k['cyan-ink'], k['out'], 4.5),
    ] + [(f'av-{i} ink / bg', k[f'av-{i}-ink'], k[f'av-{i}-bg'], 4.5) for i in range(8)]
    fails = []
    for label, a, b, need in pairs:
        r = contrast(a, b)
        if r < need:
            fails.append(f'{label} {r:.2f} < {need}')
    return fails


def main():
    css = ['/* GENERATED by tools/themes.py - edit the table there, not this file. */',
           '/* Orbit (the default) also lives in tokens.css; repeating it here lets a',
           '   preview card of Orbit render correctly inside any other theme. */']
    report, bad = [], 0
    for t in THEMES:
        k = tokens(t)
        sel = f'[data-theme="{t["id"]}"]'
        css.append(f'{sel} {{')
        css += [f'  --{name}: {value};' for name, value in k.items()]
        css.append('}')
        rules = effects_css(t)
        if rules:
            css.append(rules)
        fails = check(t, k)
        bad += len(fails)
        report.append(f"{t['name']:<12} {'OK' if not fails else 'FAIL'}" + ''.join(f'\n    - {f}' for f in fails))
    open(os.path.join(ROOT, 'css', 'themes.css'), 'w', encoding='utf-8').write('\n'.join(css) + '\n')

    import json
    reg = [dict(id=t['id'], name=t['name'], vibe=t['vibe'], dark=t['dark'], icon=t['icon'],
                swatches=[t['bg'], t['accent'], t['out'], t['second']]) for t in THEMES]
    open(os.path.join(ROOT, 'js', 'themes.js'), 'w', encoding='utf-8').write(
        '// GENERATED by tools/themes.py: the theme list the app shows.\n'
        f'window.OrbitThemes = {json.dumps(reg, indent=2, ensure_ascii=False)};\n')

    # One file per theme for the Flutter port (Phase 2) and, later, the format
    # a downloadable theme pack carries (Part C): data only, never code.
    import json as _json
    import shutil
    # orbit_ui lives in the helix_remote workspace since Part B.
    out_dir = os.path.join(ROOT, '..', '..', 'helix_remote', 'packages', 'orbit_ui',
                           'assets', 'themes')
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    for t in THEMES:
        with open(os.path.join(out_dir, t['id'] + '.json'), 'w', encoding='utf-8') as f:
            _json.dump(theme_json(t, tokens(t)), f, indent=1, ensure_ascii=False,
                       sort_keys=True)
            f.write('\n')
    print('%d theme files written' % len(THEMES))
    print('\n'.join(report))
    print(f'\n{len(THEMES)} themes, {bad} contrast failures')


if __name__ == '__main__':
    main()
