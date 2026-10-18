# The compare tool

Two halves and a page:

- **The HTML half**, `shoot_html.py` (this README, from "Running it" on),
  photographs the prototype in bare mode, one PNG per screen state, into
  `shots/`.
- **The Flutter half** is the preview app's shoot mode
  (`apps/orbit_preview/lib/shoot.dart`). The real app, with real fonts and the
  real engine, draws each ported key at the same size and writes it into
  `flutter/`. (It is not a widget test: a test draws text in its test font
  unless every font is loaded, and `toImage` never finishes under its fake
  clock.)
- **The report**: the same run compares each pair and writes `report/`: a
  difference heat map and an overlay per screen, `results.json`, and
  `index.html`, which shows the two side by side, a wipe slider and the heat
  map, worst first.

It exists because of the failure that killed the last port attempt: nobody put
the two side by side, so "looks roughly right" passed. It is a **measurement**
tool. It never edits a screen's CSS or JS to make a shot work.

## A whole comparison

```
# 1. the prototype's shot (with the prototype serving on 5317)
python orbit/flutter/tools/compare/shoot_html.py --reduce-motion --out orbit/flutter/tools/compare/shots/reduce-motion startup

# 2. build the preview app once after any Dart change
cd orbit/flutter/apps/orbit_preview && flutter build windows --debug

# 3. the Flutter shot, the comparison and the page (from orbit/flutter)
apps/orbit_preview/build/windows/x64/runner/Debug/orbit_preview.exe --shoot startup --reduce-motion --html "$PWD/tools/compare/shots/reduce-motion"

# the theme gallery, one PNG per theme, into flutter/gallery/
apps/orbit_preview/build/windows/x64/runner/Debug/orbit_preview.exe --gallery
```

Only keys listed in `apps/orbit_preview/lib/ported.dart` can be shot. Shoot
both halves with the same `--reduce-motion` setting: with it, animations rest
where the prototype's `prefers-reduced-motion` rules put them, so a moving
screen compares the same way every time. To view the page, serve the folder
(the `orbit-compare` launch configuration, port 5321) and open
`/report/index.html`; a page opened from disk cannot load the images.

**The score** is the percentage of pixels that are not byte-identical. Text
and soft shadows always differ slightly between Chrome and Flutter, so a
correct screen still scores a few percent; read the heat map, where yellow is
a small difference and red a large one.

## Running it

The prototype must be serving first:

```
python orbit/prototype/serve.py          # http://127.0.0.1:5317
```

A side session may already be serving it; just use it. Then:

```
# one screen, the phone frame, the Orbit theme
python orbit/flutter/tools/compare/shoot_html.py group

# a batch of keys in one Chrome session
python orbit/flutter/tools/compare/shoot_html.py chats chat group settings

# every state in prototype/screens.json (236 of them, about 8½ minutes)
python orbit/flutter/tools/compare/shoot_html.py --all

# the Windows layouts
python orbit/flutter/tools/compare/shoot_html.py --device window-m group
python orbit/flutter/tools/compare/shoot_html.py --device window-l group

# another theme, and the lower part of a long page
python orbit/flutter/tools/compare/shoot_html.py --theme arcade group
python orbit/flutter/tools/compare/shoot_html.py --scroll 760 settings

# somewhere else to put the images
python orbit/flutter/tools/compare/shoot_html.py --out shots/html/ --all
```

Images are named `<key>[.scroll<n>].<device>.<theme>.png`, so a key shot at two
scroll offsets keeps both. Every run also writes `manifest.json` in `--out`
(next to the images): the browser, the base URL, the device size, and per
state the file, its pixel and byte size, how long readiness took, whether the
fonts loaded, whether the page had settled, how many elements were drawn, and
how many attempts it took. That is what the compare page should read, and it is
also how you tell a good batch from a bad one. The exit code is 1 if any state
failed.

`--help` lists every option. The ones that matter:

| Option | What it does |
|---|---|
| `--all` | every key in `prototype/screens.json` |
| `--device phone\|window-m\|window-l` | 412×866, 960×720, 1280×800 |
| `--theme <id>` | any theme id (default `orbit`) |
| `--scroll <px>` | scrolls the open page, and waits until it has |
| `--full-window` | shoot the whole browser window, not just the device |
| `--chrome <path>` | the browser binary, if it is not the usual Chrome |
| `--profile <dir>` | reuse a profile directory (warms the font cache) |
| `--reduce-motion` | emulates `prefers-reduced-motion: reduce` (see below) |
| `--no-wait` | capture without waiting for readiness. Only to show the failure mode; do not use it for real shots |

## How readiness works

Headless Chrome can photograph a page before every script has loaded. That is
the documented failure mode from Phase 1b: the shot comes out blank or
unstyled, and it looks like a design bug rather than a tooling bug.

So the page says when it is ready. `orbit/prototype/js/boot.js` sets
`window.__orbitReady = true` once:

- `document.fonts.ready` has settled (Geist and the rest come from Google
  Fonts, so without this a shot can have the fallback font),
- two animation frames have run, so the first frame is painted (best effort in
  a headless browser, which does not run frames until something asks for one),
- and a `?scroll=` request has been applied, because `App.boot` scrolls a beat
  after it starts.

`window.__orbitReadyInfo` beside it says what happened (`fonts: loaded |
timeout`, `frames: painted | not-painted`, `scroll: applied | unreached |
none`), and the tool copies that into the manifest.

That block is purely additive: it sets two properties on `window` and reads the
DOM. It adds no node, no class and no style, so it cannot change what a screen
draws.

`shoot_html.py` polls that flag over the DevTools protocol - it never sleeps a
fixed number of seconds and hopes. Then it waits for the page to **stop
moving**: two small captures in a row that are byte-identical (bounded, because
a blinking cursor never settles), and finally takes the real one.

Proof that the wait matters, in `shots/_sample/`. It is not committed;
`shoot_html.py --out shots/_sample/ group` and `shoot_html.py --out
shots/_sample/too-early/ --no-wait group` remake it. Both are the same key, the same
device and the same theme; the only difference is whether the flag was polled:

| | `shots/_sample/group.phone.orbit.png` | `shots/_sample/too-early/group.phone.orbit.png` |
|---|---|---|
| how | waited for the flag | `--no-wait` |
| `readyFlag` seen before capture | `true` | `false` |
| time to ready | 1,712 ms | 147 ms |
| PNG | 412×866, 49,683 bytes | 412×866, 10,152 bytes |
| nodes drawn in the phone | 584 | 20 |
| fonts | loaded | not loaded yet |
| what you see | the Family group conversation | the viewer chrome, no CSS, an empty phone |

The early shot is not blank, it is *unstyled*, and it is 10 kB rather than 2 kB,
so **no size threshold can be relied on to catch this**. Only the readiness
poll catches it. That is why the poll is the gate and the size checks are only
a backstop.

## Gotchas found the hard way

- **Chrome must be told which binary.** The tool looks in the same places as
  `prototype/tools/shoot.py` (`C:\Program Files\Google\Chrome\Application`,
  Edge, then the Linux paths). Pass `--chrome <path>` for anything else.
- **It launches Chrome itself, in its own profile directory**, never your
  browser's. A fresh temporary profile per run means no leftover device,
  theme or tweaks from a previous visit. Do not kill "the Chrome" to clean up
  after this tool.
- **The page caches.** `serve.py` sends `Cache-Control: no-store`, but the
  Google Fonts stylesheet and the five unpkg icon stylesheets are cross-origin,
  and the browser caches those. That fetch is most of the 1.2 s of readiness
  per state, and it does not get cheaper within a run; `--profile <dir>` pays
  for it once and reuses it.
- **Blank or unstyled shots mean a failed capture, not a failed design.** The
  tool retries a state once, and reports what went wrong in `reason`. If a
  state still fails, the reason usually names a page error (a script threw),
  because the tool collects page errors on purpose.
- **A navigation can be dropped.** `Page.navigate` is fire and forget, and one
  issued while the previous is still in flight is sometimes dropped; the page
  then sits on the old document and the readiness flag never appears. The tool
  checks the address after every navigation and re-issues it, and it hops
  through `about:blank` first, because a navigation that only changes the
  fragment is same-document and would otherwise photograph the previous screen.
- **Headless Chrome does not run animation frames until something asks for
  one.** `boot.js` therefore treats "the first frame is painted" as best effort
  (500 ms) and records which happened as `frames: painted | not-painted`. The
  screenshot itself asks for a frame, so the picture is complete either way; the
  settle step is what makes sure nothing was still moving when it was taken.
- **Shoot the prototype when nobody is editing it.** If a script is saved while a
  batch is running, a state can fail with a page error from a half-written file
  (seen once, mid-run). It is in `reason`; shoot that state again.
- **One state at a time, one Chrome.** All 236 states took 8½ minutes on this
  machine (about 1.2 s of that is the Google Fonts fetch; readiness was under
  2.8 s for 95% of them). Do not add parallelism: two pages sharing a browser
  is how a shot catches a half-painted frame.
- **A phone shot is 412 px wide**, cut from a 640 px window, because Chrome
  will not make a window narrower than about 500 px. `--full-window` gives the
  whole 640×866 window that `tools/shoot.py` produces, with the device at the
  left.
- **Fonts and icons come from the network.** Google Fonts (Geist, DM Sans,
  Fraunces, …) and unpkg (Phosphor icons). Offline, the shots fall back to
  system fonts and the icons are missing, and they will not match the Flutter
  side, which bundles its fonts. Check `fonts: timeout` in the manifest.
- **Animated states are shot at an arbitrary point** in the loop (typing dots,
  a pulsing dot, skeleton shimmer, the Terminal cursor). `--reduce-motion`
  emulates `prefers-reduced-motion: reduce`, which freezes animation and
  transition inside the phone screen and makes those states repeatable. It is
  **off by default**, because it changes what is measured. Turn it on only for
  the states that animate, and say so when you show the shots.
- **`scroll` needs a scrollable element.** `?scroll=` scrolls the first
  `.scroll` or `.timeline` on the page. A screen that does not scroll reports
  `scroll: unreached` in the manifest; the shot is the top of the page, which
  is what that screen is.

## Dependencies

Python 3 and the Chrome binary. Nothing else: no pip packages, no Pillow. The
DevTools protocol client (a small RFC 6455 websocket) is in the tool itself,
and a PNG's width, height and size are read from its header - the blank check
is a byte count, calibrated at 6,000, below the smallest real screen in the
236-state batch (10.2 kB, `media-not-here`).

The comparison decodes pixels in Dart (`packages/orbit_ui/lib/src/compare/`,
its own PNG reader and writer), so the Python half still needs nothing else.
The Flutter half needs the preview app built for Windows, which needs Visual
Studio's C++ tools, as `flutter build windows` does anywhere.
