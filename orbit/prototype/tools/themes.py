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
    return "url(\"data:image/svg+xml," + urllib.parse.quote(svg, safe=" =:/'#,.()-") + "\")"


NOISE = lambda r, g, b, a: svg_url(
    f"<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.85' numOctaves='3' stitchTiles='stitch'/>"
    f"<feColorMatrix values='0 0 0 0 {r} 0 0 0 0 {g} 0 0 0 0 {b} 0 0 0 {a} 0'/></filter><rect width='100%' height='100%' filter='url(#n)'/></svg>")

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
         radii=dict(xs=6, sm=10, md=14, lg=18, xl=24, pill=999), avatar='18%', bubble=10, cut=5,
         pattern='none', pattern_size='auto', glow='0 0 0 transparent', extra='',
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
         radii=dict(xs=6, sm=10, md=14, lg=18, xl=24, pill=999), avatar='18%', bubble=10, cut=5,
         pattern='none', pattern_size='auto', glow='0 0 0 transparent', extra=''),

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
         pattern=NOISE(0.55, 0.35, 0.3, 0.06), pattern_size='160px 160px', glow='0 0 0 transparent',
         extra='''
[data-theme="bloom"] .wordmark { font-style: italic; }
[data-theme="bloom"] .day span { font-family: var(--font-display); font-style: italic; text-transform: none; letter-spacing: 0; font-size: 13px; }
'''),

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
         pattern=svg_url("<svg xmlns='http://www.w3.org/2000/svg' width='64' height='64'><path d='M16 20c-2-3-7-2-7 2 0 3 4 5 7 8 3-3 7-5 7-8 0-4-5-5-7-2z' fill='#FFB3D1' fill-opacity='.4'/>"
                         "<path d='M46 40l1.6 3.4 3.4 1.6-3.4 1.6L46 50l-1.6-3.4L41 45l3.4-1.6z' fill='#B9A2FF' fill-opacity='.45'/><circle cx='50' cy='14' r='1.6' fill='#7FD0F5' fill-opacity='.5'/></svg>"),
         pattern_size='64px 64px', glow='0 0 0 transparent',
         extra='''
[data-theme="mochi"] .wordmark::after { content: " ♡"; -webkit-text-fill-color: #FF8FC0; font-size: 0.62em; }
[data-theme="mochi"] .bubble { font-weight: 600; }
[data-theme="mochi"] .dock { border: 2px solid #FFD1E6; }
[data-theme="mochi"] .day span::before { content: "✦ "; color: #FF8FC0; }
'''),

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
         pattern=NOISE(0.24, 0.17, 0.1, 0.10), pattern_size='160px 160px', glow='0 0 0 transparent',
         extra='''
[data-theme="papyrus"] .page { background-image: var(--chat-pattern); background-size: var(--chat-pattern-size); }
[data-theme="papyrus"] .phone-screen, [data-theme="papyrus"] { font-size: 16px; }
[data-theme="papyrus"] .day span::before { content: "❦ "; }
[data-theme="papyrus"] .day span::after { content: " ❦"; }
[data-theme="papyrus"] .card, [data-theme="papyrus"] .hero-card { box-shadow: inset 0 0 0 3px var(--surface), inset 0 0 0 4px var(--line); }
'''),

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
         pattern='linear-gradient(rgba(255, 46, 136, 0.07) 1px, transparent 1px), linear-gradient(90deg, rgba(0, 229, 255, 0.06) 1px, transparent 1px)', pattern_size='28px 28px',
         glow='0 0 18px rgba(0, 229, 255, 0.45)',
         extra='''
[data-theme="arcade"] .msg.in .bubble { box-shadow: 0 0 14px rgba(0, 229, 255, 0.16); }
[data-theme="arcade"] .msg.out .bubble { box-shadow: 0 0 14px rgba(255, 46, 136, 0.24); }
[data-theme="arcade"] .wordmark { filter: drop-shadow(0 0 10px rgba(122, 92, 255, 0.6)); }
[data-theme="arcade"] .btn.primary, [data-theme="arcade"] .xfab { clip-path: polygon(10px 0, 100% 0, 100% calc(100% - 10px), calc(100% - 10px) 100%, 0 100%, 0 10px); border-radius: 0; box-shadow: none; }
[data-theme="arcade"] .eyebrow, [data-theme="arcade"] .day span { color: var(--accent-ink); }
'''),

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
         pattern='repeating-linear-gradient(0deg, rgba(57, 255, 136, 0.045) 0 1px, transparent 1px 3px)', pattern_size='auto',
         glow='0 0 14px rgba(57, 255, 136, 0.35)',
         extra='''
[data-theme="terminal"] .wordmark { filter: drop-shadow(0 0 8px rgba(57, 255, 136, 0.45)); }
[data-theme="terminal"] .wordmark::after { content: "_"; -webkit-text-fill-color: var(--accent); animation: blink 1s infinite; }
[data-theme="terminal"] .day span::before { content: "[ "; }
[data-theme="terminal"] .day span::after { content: " ]"; }
[data-theme="terminal"] .group-title.eyebrow::before { content: "# "; }
'''),

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
         pattern=svg_url("<svg xmlns='http://www.w3.org/2000/svg' width='220' height='220'><g fill='none' stroke='#323B29' stroke-width='1.3'>"
                         "<path d='M-10 110c25-45 65-55 100-32s70 12 80-22 40-30 60-10'/><path d='M-10 150c35-32 78-38 112-16s62 6 88-26 30-22 40-14'/>"
                         "<path d='M-10 70c28-28 60-33 88-12s56 2 78-32 40-20 70-8'/><path d='M-10 195c38-22 82-28 115-6s66 10 104-16'/><path d='M-10 30c30-20 66-24 96-4s60 0 80-26'/></g></svg>"),
         pattern_size='220px 220px', glow='0 0 0 transparent',
         extra='''
[data-theme="field"] .msg.in .bubble { border-left: 3px solid #6B7A45; }
[data-theme="field"] .msg.out .bubble { border-right: 3px solid var(--accent); }
[data-theme="field"] .group-title.eyebrow::before { content: "▸ "; color: var(--accent); }
'''),
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
        'chat-pattern': t['pattern'], 'chat-pattern-size': t['pattern_size'], 'glow': t['glow'],
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
        if t['extra'].strip():
            css.append(t['extra'].strip())
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
    print('\n'.join(report))
    print(f'\n{len(THEMES)} themes, {bad} contrast failures')


if __name__ == '__main__':
    main()
