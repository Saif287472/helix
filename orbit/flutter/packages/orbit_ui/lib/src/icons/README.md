# Orbit icons

The prototype is the specification: every icon here is one the prototype
draws with a Phosphor class, mapped to the exact symbol `phosphor_flutter`
2.1.0 generates. `orbit_icons.dart` is the machine-readable version of this
table; it is generated from the same list.

## How the prototype names and weights an icon

`prototype/js/ui.js` line 14 is the whole rule:

```js
const icon = (name, weight = '') => { const w = weight || themeWeight;
  return `<i class="ph${w ? '-' + w : ''} ph-${name}" aria-hidden="true"></i>`; };
```

- `icon('seal-check', 'fill')` is the prototype's `ph-fill ph-seal-check`.
- `icon('check')` with no weight falls back to `themeWeight`, which
  `prototype/js/themes.js` sets per theme (regular for Orbit/Orbit Night,
  light for Bloom/Papyrus/Terminal, duotone for Mochi, bold for Arcade/Field).
- A few places write the class out by hand (`<i class="ph ph-checks tick">`).

`phosphor_flutter` exposes weights as six separate classes with `static const`
fields (`PhosphorIconsRegular.check`, `PhosphorIconsFill.check`, ...) and a
`PhosphorIcons.check([style])` switch. There is no `.fill` getter, so
`OrbitIcons` mirrors the package: the bare name is the regular weight, and
each other weight the prototype asks for gets its own constant
(`OrbitIcons.checkBold`, `OrbitIcons.checkFill`). Every icon has its regular
entry even where the prototype only draws another weight, so the bare name
is always there - two of the themes (Orbit, Orbit Night) use regular as the
default. No weight is emitted beyond regular unless the prototype asks for
it.

`OrbitIcons.check` is a `PhosphorIconData`, so it goes straight into an
`Icon` or a `PhosphorIcon`. Render duotone with `PhosphorIcon`, which draws
the secondary layer; a plain `Icon` on a duotone constant shows only the
front layer.

## The table

164 icons, all mapped.

| Prototype name | Weight(s) used | Dart symbol(s) |
| --- | --- | --- |
| `address-book` | `regular`, `fill` | `OrbitIcons.addressBook`, `OrbitIcons.addressBookFill` |
| `app-window` | `regular`, `fill` | `OrbitIcons.appWindow`, `OrbitIcons.appWindowFill` |
| `archive` | `regular`, `fill` | `OrbitIcons.archive`, `OrbitIcons.archiveFill` |
| `arrow-bend-up-left` | `regular`, `bold` | `OrbitIcons.arrowBendUpLeft`, `OrbitIcons.arrowBendUpLeftBold` |
| `arrow-bend-up-right` | `regular`, `bold` | `OrbitIcons.arrowBendUpRight`, `OrbitIcons.arrowBendUpRightBold` |
| `arrow-circle-up` | `regular` | `OrbitIcons.arrowCircleUp` |
| `arrow-clockwise` | `regular`, `bold` | `OrbitIcons.arrowClockwise`, `OrbitIcons.arrowClockwiseBold` |
| `arrow-counter-clockwise` | `regular`, `bold` | `OrbitIcons.arrowCounterClockwise`, `OrbitIcons.arrowCounterClockwiseBold` |
| `arrow-down-left` | `regular`, `bold` | `OrbitIcons.arrowDownLeft`, `OrbitIcons.arrowDownLeftBold` |
| `arrow-left` | `regular` | `OrbitIcons.arrowLeft` |
| `arrow-square-out` | `regular` | `OrbitIcons.arrowSquareOut` |
| `arrow-up-right` | `regular`, `bold` | `OrbitIcons.arrowUpRight`, `OrbitIcons.arrowUpRightBold` |
| `arrows-clockwise` | `regular` | `OrbitIcons.arrowsClockwise` |
| `at` | `regular`, `bold` | `OrbitIcons.at`, `OrbitIcons.atBold` |
| `backspace` | `regular` | `OrbitIcons.backspace` |
| `battery-high` | `regular`, `fill` | `OrbitIcons.batteryHigh`, `OrbitIcons.batteryHighFill` |
| `bell` | `regular` | `OrbitIcons.bell` |
| `bell-ringing` | `regular`, `fill` | `OrbitIcons.bellRinging`, `OrbitIcons.bellRingingFill` |
| `bell-slash` | `regular` | `OrbitIcons.bellSlash` |
| `bluetooth` | `regular`, `fill` | `OrbitIcons.bluetooth`, `OrbitIcons.bluetoothFill` |
| `book-open-text` | `regular` | `OrbitIcons.bookOpenText` |
| `bug` | `regular` | `OrbitIcons.bug` |
| `calendar-blank` | `regular` | `OrbitIcons.calendarBlank` |
| `camera` | `regular`, `fill` | `OrbitIcons.camera`, `OrbitIcons.cameraFill` |
| `camera-plus` | `regular`, `fill` | `OrbitIcons.cameraPlus`, `OrbitIcons.cameraPlusFill` |
| `camera-rotate` | `regular`, `fill` | `OrbitIcons.cameraRotate`, `OrbitIcons.cameraRotateFill` |
| `camera-slash` | `regular` | `OrbitIcons.cameraSlash` |
| `caret-down` | `regular`, `bold` | `OrbitIcons.caretDown`, `OrbitIcons.caretDownBold` |
| `caret-left` | `regular`, `bold` | `OrbitIcons.caretLeft`, `OrbitIcons.caretLeftBold` |
| `caret-right` | `regular` | `OrbitIcons.caretRight` |
| `caret-up` | `regular`, `bold` | `OrbitIcons.caretUp`, `OrbitIcons.caretUpBold` |
| `cell-signal-full` | `regular`, `fill` | `OrbitIcons.cellSignalFull`, `OrbitIcons.cellSignalFullFill` |
| `cell-signal-low` | `regular`, `fill` | `OrbitIcons.cellSignalLow`, `OrbitIcons.cellSignalLowFill` |
| `chart-bar-horizontal` | `regular` | `OrbitIcons.chartBarHorizontal` |
| `chat-centered-text` | `regular`, `fill` | `OrbitIcons.chatCenteredText`, `OrbitIcons.chatCenteredTextFill` |
| `chat-circle` | `regular`, `fill` | `OrbitIcons.chatCircle`, `OrbitIcons.chatCircleFill` |
| `chat-circle-dots` | `regular`, `bold` | `OrbitIcons.chatCircleDots`, `OrbitIcons.chatCircleDotsBold` |
| `chat-circle-slash` | `regular` | `OrbitIcons.chatCircleSlash` |
| `chat-dots` | `regular` | `OrbitIcons.chatDots` |
| `chats` | `regular` | `OrbitIcons.chats` |
| `chats-circle` | `regular` | `OrbitIcons.chatsCircle` |
| `check` | `regular`, `bold` | `OrbitIcons.check`, `OrbitIcons.checkBold` |
| `check-circle` | `regular`, `fill` | `OrbitIcons.checkCircle`, `OrbitIcons.checkCircleFill` |
| `checks` | `regular`, `fill`, `bold` | `OrbitIcons.checks`, `OrbitIcons.checksFill`, `OrbitIcons.checksBold` |
| `circle` | `regular` | `OrbitIcons.circle` |
| `clipboard-text` | `regular` | `OrbitIcons.clipboardText` |
| `clock` | `regular` | `OrbitIcons.clock` |
| `clock-counter-clockwise` | `regular` | `OrbitIcons.clockCounterClockwise` |
| `cloud-arrow-down` | `regular` | `OrbitIcons.cloudArrowDown` |
| `cloud-arrow-up` | `regular` | `OrbitIcons.cloudArrowUp` |
| `cloud-check` | `regular` | `OrbitIcons.cloudCheck` |
| `cloud-slash` | `regular` | `OrbitIcons.cloudSlash` |
| `cloud-x` | `regular` | `OrbitIcons.cloudX` |
| `code` | `regular` | `OrbitIcons.code` |
| `copy` | `regular` | `OrbitIcons.copy` |
| `crown-simple` | `regular` | `OrbitIcons.crownSimple` |
| `database` | `regular` | `OrbitIcons.database` |
| `desktop` | `regular`, `fill` | `OrbitIcons.desktop`, `OrbitIcons.desktopFill` |
| `device-mobile` | `regular`, `fill` | `OrbitIcons.deviceMobile`, `OrbitIcons.deviceMobileFill` |
| `devices` | `regular`, `fill` | `OrbitIcons.devices`, `OrbitIcons.devicesFill` |
| `dots-nine` | `regular`, `bold` | `OrbitIcons.dotsNine`, `OrbitIcons.dotsNineBold` |
| `dots-three-vertical` | `regular` | `OrbitIcons.dotsThreeVertical` |
| `download-simple` | `regular`, `fill`, `bold` | `OrbitIcons.downloadSimple`, `OrbitIcons.downloadSimpleFill`, `OrbitIcons.downloadSimpleBold` |
| `ear` | `regular`, `fill` | `OrbitIcons.ear`, `OrbitIcons.earFill` |
| `eraser` | `regular` | `OrbitIcons.eraser` |
| `export` | `regular` | `OrbitIcons.export` |
| `eye` | `regular` | `OrbitIcons.eye` |
| `eye-slash` | `regular` | `OrbitIcons.eyeSlash` |
| `file-pdf` | `regular` | `OrbitIcons.filePdf` |
| `file-text` | `regular`, `fill` | `OrbitIcons.fileText`, `OrbitIcons.fileTextFill` |
| `fingerprint` | `regular` | `OrbitIcons.fingerprint` |
| `flag` | `regular` | `OrbitIcons.flag` |
| `gear-six` | `regular` | `OrbitIcons.gearSix` |
| `gif` | `regular` | `OrbitIcons.gif` |
| `globe-simple` | `regular` | `OrbitIcons.globeSimple` |
| `hand-pointing` | `regular` | `OrbitIcons.handPointing` |
| `hard-drives` | `regular`, `fill` | `OrbitIcons.hardDrives`, `OrbitIcons.hardDrivesFill` |
| `headphones` | `regular`, `fill` | `OrbitIcons.headphones`, `OrbitIcons.headphonesFill` |
| `hourglass-medium` | `regular`, `fill` | `OrbitIcons.hourglassMedium`, `OrbitIcons.hourglassMediumFill` |
| `identification-card` | `regular` | `OrbitIcons.identificationCard` |
| `image` | `regular` | `OrbitIcons.image` |
| `images` | `regular`, `fill` | `OrbitIcons.images`, `OrbitIcons.imagesFill` |
| `info` | `regular` | `OrbitIcons.info` |
| `key` | `regular`, `fill` | `OrbitIcons.key`, `OrbitIcons.keyFill` |
| `keyboard` | `regular` | `OrbitIcons.keyboard` |
| `lightning` | `regular`, `fill` | `OrbitIcons.lightning`, `OrbitIcons.lightningFill` |
| `link-break` | `regular`, `fill` | `OrbitIcons.linkBreak`, `OrbitIcons.linkBreakFill` |
| `link-simple` | `regular` | `OrbitIcons.linkSimple` |
| `link-simple-horizontal` | `regular` | `OrbitIcons.linkSimpleHorizontal` |
| `list` | `regular` | `OrbitIcons.list` |
| `lock-key` | `regular`, `fill` | `OrbitIcons.lockKey`, `OrbitIcons.lockKeyFill` |
| `lock-simple` | `regular`, `fill` | `OrbitIcons.lockSimple`, `OrbitIcons.lockSimpleFill` |
| `lock-simple-open` | `regular` | `OrbitIcons.lockSimpleOpen` |
| `magnifying-glass` | `regular`, `bold` | `OrbitIcons.magnifyingGlass`, `OrbitIcons.magnifyingGlassBold` |
| `magnifying-glass-minus` | `regular` | `OrbitIcons.magnifyingGlassMinus` |
| `map-pin` | `regular`, `fill` | `OrbitIcons.mapPin`, `OrbitIcons.mapPinFill` |
| `microphone` | `regular`, `fill` | `OrbitIcons.microphone`, `OrbitIcons.microphoneFill` |
| `microphone-slash` | `regular`, `fill` | `OrbitIcons.microphoneSlash`, `OrbitIcons.microphoneSlashFill` |
| `minus` | `regular`, `light` | `OrbitIcons.minus`, `OrbitIcons.minusLight` |
| `monitor` | `regular` | `OrbitIcons.monitor` |
| `music-note` | `regular` | `OrbitIcons.musicNote` |
| `number-circle-one` | `regular` | `OrbitIcons.numberCircleOne` |
| `palette` | `regular`, `fill` | `OrbitIcons.palette`, `OrbitIcons.paletteFill` |
| `paper-plane-tilt` | `regular`, `fill` | `OrbitIcons.paperPlaneTilt`, `OrbitIcons.paperPlaneTiltFill` |
| `paperclip` | `regular` | `OrbitIcons.paperclip` |
| `password` | `regular`, `fill` | `OrbitIcons.password`, `OrbitIcons.passwordFill` |
| `pause` | `regular`, `fill` | `OrbitIcons.pause`, `OrbitIcons.pauseFill` |
| `pencil-simple` | `regular`, `bold` | `OrbitIcons.pencilSimple`, `OrbitIcons.pencilSimpleBold` |
| `phone` | `regular`, `fill` | `OrbitIcons.phone`, `OrbitIcons.phoneFill` |
| `phone-call` | `regular` | `OrbitIcons.phoneCall` |
| `phone-disconnect` | `regular`, `fill`, `bold` | `OrbitIcons.phoneDisconnect`, `OrbitIcons.phoneDisconnectFill`, `OrbitIcons.phoneDisconnectBold` |
| `phone-incoming` | `regular`, `fill` | `OrbitIcons.phoneIncoming`, `OrbitIcons.phoneIncomingFill` |
| `phone-plus` | `regular`, `bold` | `OrbitIcons.phonePlus`, `OrbitIcons.phonePlusBold` |
| `phone-x` | `regular` | `OrbitIcons.phoneX` |
| `play` | `regular`, `fill` | `OrbitIcons.play`, `OrbitIcons.playFill` |
| `play-circle` | `regular`, `fill` | `OrbitIcons.playCircle`, `OrbitIcons.playCircleFill` |
| `plus` | `regular`, `bold` | `OrbitIcons.plus`, `OrbitIcons.plusBold` |
| `prohibit` | `regular`, `fill` | `OrbitIcons.prohibit`, `OrbitIcons.prohibitFill` |
| `push-pin` | `regular`, `fill` | `OrbitIcons.pushPin`, `OrbitIcons.pushPinFill` |
| `qr-code` | `regular`, `fill` | `OrbitIcons.qrCode`, `OrbitIcons.qrCodeFill` |
| `question` | `regular` | `OrbitIcons.question` |
| `radio-button` | `regular` | `OrbitIcons.radioButton` |
| `scan` | `regular` | `OrbitIcons.scan` |
| `scroll` | `regular` | `OrbitIcons.scroll` |
| `seal-check` | `regular`, `fill` | `OrbitIcons.sealCheck`, `OrbitIcons.sealCheckFill` |
| `share-network` | `regular` | `OrbitIcons.shareNetwork` |
| `shield` | `regular` | `OrbitIcons.shield` |
| `shield-check` | `regular`, `fill` | `OrbitIcons.shieldCheck`, `OrbitIcons.shieldCheckFill` |
| `shield-star` | `regular` | `OrbitIcons.shieldStar` |
| `shield-warning` | `regular`, `fill` | `OrbitIcons.shieldWarning`, `OrbitIcons.shieldWarningFill` |
| `sign-in` | `regular` | `OrbitIcons.signIn` |
| `sign-out` | `regular` | `OrbitIcons.signOut` |
| `siren` | `regular` | `OrbitIcons.siren` |
| `sliders-horizontal` | `regular` | `OrbitIcons.slidersHorizontal` |
| `smiley` | `regular` | `OrbitIcons.smiley` |
| `speaker-high` | `regular`, `fill` | `OrbitIcons.speakerHigh`, `OrbitIcons.speakerHighFill` |
| `speaker-slash` | `regular` | `OrbitIcons.speakerSlash` |
| `spinner-gap` | `regular`, `bold` | `OrbitIcons.spinnerGap`, `OrbitIcons.spinnerGapBold` |
| `square` | `regular`, `light` | `OrbitIcons.square`, `OrbitIcons.squareLight` |
| `sticker` | `regular` | `OrbitIcons.sticker` |
| `tag` | `regular` | `OrbitIcons.tag` |
| `timer` | `regular` | `OrbitIcons.timer` |
| `trash` | `regular`, `fill` | `OrbitIcons.trash`, `OrbitIcons.trashFill` |
| `trash-simple` | `regular` | `OrbitIcons.trashSimple` |
| `tray-arrow-up` | `regular`, `fill` | `OrbitIcons.trayArrowUp`, `OrbitIcons.trayArrowUpFill` |
| `upload-simple` | `regular`, `bold` | `OrbitIcons.uploadSimple`, `OrbitIcons.uploadSimpleBold` |
| `user` | `regular` | `OrbitIcons.user` |
| `user-circle` | `regular` | `OrbitIcons.userCircle` |
| `user-circle-dashed` | `regular` | `OrbitIcons.userCircleDashed` |
| `user-circle-gear` | `regular` | `OrbitIcons.userCircleGear` |
| `user-circle-plus` | `regular` | `OrbitIcons.userCirclePlus` |
| `user-minus` | `regular` | `OrbitIcons.userMinus` |
| `user-plus` | `regular`, `bold` | `OrbitIcons.userPlus`, `OrbitIcons.userPlusBold` |
| `users-three` | `regular`, `fill`, `bold` | `OrbitIcons.usersThree`, `OrbitIcons.usersThreeFill`, `OrbitIcons.usersThreeBold` |
| `vibrate` | `regular` | `OrbitIcons.vibrate` |
| `video-camera` | `regular`, `fill` | `OrbitIcons.videoCamera`, `OrbitIcons.videoCameraFill` |
| `video-camera-slash` | `regular`, `fill` | `OrbitIcons.videoCameraSlash`, `OrbitIcons.videoCameraSlashFill` |
| `warning` | `regular`, `fill` | `OrbitIcons.warning`, `OrbitIcons.warningFill` |
| `warning-circle` | `regular`, `fill` | `OrbitIcons.warningCircle`, `OrbitIcons.warningCircleFill` |
| `wifi-high` | `regular`, `fill` | `OrbitIcons.wifiHigh`, `OrbitIcons.wifiHighFill` |
| `wifi-slash` | `regular` | `OrbitIcons.wifiSlash` |
| `wrench` | `regular` | `OrbitIcons.wrench` |
| `x` | `regular`, `bold`, `light` | `OrbitIcons.x`, `OrbitIcons.xBold`, `OrbitIcons.xLight` |
| `x-circle` | `regular` | `OrbitIcons.xCircle` |

## UNMAPPED

None. Every Phosphor name the prototype uses exists in `phosphor_flutter`
2.1.0, which ships all 1512 icons in all six weights (thin, light, regular,
bold, fill, duotone).

If a screen needs an icon the prototype does not have, that is a design
question, not a mapping problem: ask, and record the answer in
`orbit/DEVIATIONS.md`.

## Naming traps

Things that cost time while mapping this, and would again:

1. **The web name and the Dart name are the same words, not the same string.**
   They agree on word boundaries and capitals, but the web CSS class is
   kebab-case and the Dart field is lowerCamelCase: `ph-seal-check` is
   `PhosphorIcons.sealCheck`. There is no exception in this set, but the
   safest way to find the exact symbol is to look for the icon's asset name
   in the doc comment the package generates, e.g.
   `/// regular: ![seal-check](.../assets/regular/seal-check.svg)` above
   `static PhosphorIconData sealCheck(`.
2. **The package already carries the Phosphor 2 renames.** Phosphor 2
   renamed `cog` to `gear-six` (conversation chat-settings menu), and the
   prototype uses the new names, so `OrbitIcons.gearSix` is right and there
   is no `cog` to look for.
3. **`chats` and `chats-circle` are two different icons.** `ph-chats`
   (`OrbitIcons.chats`, the plain speech bubble) appears once, in the
   Delete-account list; `ph-chats-circle` (`OrbitIcons.chatsCircle`) is the
   Chats dock tab. Easy to merge by eye, so check the class name.
4. **`chat-circle`, `chat-circle-dots` and `chat-circle-slash` are all
   separate icons** (message button, the FAB, "Message not found").
5. **`user`, `users-three`, `user-circle`, `user-circle-dashed`,
   `user-circle-gear` and `user-circle-plus` are six separate icons.**
   `users-three` doubles as the group-avatar glyph, where it is fill.
6. **The prototype's photo placeholders are not icons.** `ph-a` to `ph-f`
   are CSS gradient classes on the fake chat photos (`css/screens.css`),
   and `ph-fill` / `ph-bold` / `ph-light` are weight classes. A grep for
   `ph-` finds both; they are not Phosphor icons and are not in this table.
   The same is true of strings that are not icons at all: `interactions`
   rows end in a device name (`'phone', 'window'`), `you.js` `ROWS`
   starts with a route name (`'storage', 'database'` - the icon there is
   `database`), and `tool/` is not a screen.
7. **`check` is the prototype's tick and `checks` is the double tick.**
   They are used differently everywhere: `check` for "done" and delivery
   sent, `checks` for delivered and read. Getting them backwards is easy
   because the glyphs look alike at 12 px.
8. **`arrow-square-out`, `arrow-clockwise` and `arrows-clockwise` are all
   distinct** (open a document, retry one transfer, refresh a list).

## Where a few icons are used

Only the ones that are easy to misread, or that a port might drop:

- `app-window` - startup: "Orbit is open elsewhere"
- `arrow-circle-up` - chat preview label for an unsupported message ("needs a newer version")
- `backspace` - calls keypad (dial pad)
- `cell-signal-low` - in-call "Poor connection" chip
- `chat-centered-text` - You > Chats tile and the Chats settings hero
- `chat-circle-dots` - the FAB on the Chats tab
- `chat-dots` - Privacy > Typing indicator switch (topics)
- `chats` - Delete-account consequences list (settings)
- `chats-circle` - dock tab (Chats), empty chats list
- `cloud-x` - Delete-account consequences list (settings)
- `ear` - call audio-output sheet (earpiece)
- `eraser` - chat settings > Clear chat
- `gear-six` - chat settings menu. Phosphor renamed `cog` to `gear-six`; the Dart name is the same.
- `hand-pointing` - history-transfer hero pill
- `hourglass-medium` - group join "Request sent", field lockout, lookup limit
- `identification-card` - You > Edit profile search row
- `lightning` - group invite link card ("Joins straight away")
- `number-circle-one` - View once row (send files)
- `seal-check` - chat row, contact and conversation headers ("Safety number verified")
- `smiley` - composer emoji toggle
- `user` - profile visibility rows (Name / About / ~name / number)
- `vibrate` - Notifications > Vibrate switch
- `x-circle` - remove-a-device row, device removed in activity

## Not ported: the prototype's own chrome

`prototype/index.html` draws a few icons for the *prototype harness*, not
for Orbit: the screen filter (`magnifying-glass`), the Screens / Tweaks
chips (`list`, `sliders-horizontal`), the device picker (`device-mobile`,
`app-window`, `monitor`), the fake window bar (`minus`, `square`, `x` at
light) and the fake phone status bar (`cell-signal-full`, `wifi-high`,
`battery-high` at fill). They are mapped above because they are in the
prototype, but Orbit draws none of them: the real status bar and window
chrome belong to the platform.

## Regenerating

Do not hand-add an entry. Re-derive it from the prototype (`grep -rn "ph-"
`prototype/js prototype/index.html`, plus every `icon(...)` / `ibtn(...)`
call and every data table that carries an icon name), look the symbol up in
`phosphor_flutter/lib/src/phosphor_icons_<weight>.dart`, then add it here
and to `orbit_icons.dart`.
