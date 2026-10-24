# Sweep 14e — app `core/platform/`: the players and the microphone

**Where:** `helix_remote/app/lib/core/platform/` — `audio_player.dart` (78),
`device_audio_player.dart` (243), `voice_recorder.dart` (156),
`device_voice_recorder.dart` (280), `video_player.dart` (110),
`device_video_player.dart` (112), `chat_platform.dart` (64) — 1,043 lines.
Cross-reads: `features/conversation/application/audio_playback.dart` (194) and
`video_session.dart` (210) as the two consumers, the `record` 7.1.1 and
`record_android` 2.2.0 source (`onCaptureFailure`, the interruption policy) and
`audioplayers` 6.8.1 / `audioplayers_windows` 4.4.1 (`onDurationChanged`,
`SetPlaybackRate`).

Both players and the recorder are drawn the right way round: an interface in
`core/platform`, the plugin behind it in one file, a backend interface beneath
that so the state machine is tested without a speaker or a microphone. The video
player's state is a `ValueNotifier` with value equality, disposal is idempotent,
completion puts the position back at zero, and the recorder's clock banks
paused time rather than subtracting it. The two findings are failures that are
read as something else: a refused setting read as "this file cannot play", and a
capture failure read as "still recording".

## Findings

### AUD-14e-1 A refused playback speed makes an otherwise playable file "unavailable"

**Severity:** P3  **Confidence:** confirmed
**Where:**
[device_audio_player.dart:155-168](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/device_audio_player.dart#L155-L168)
(`load`), [device_audio_player.dart:207-216](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/device_audio_player.dart#L207-L216)
(`setSpeed`, which already tolerates refusal).
**What:** `load` stops the backend, sets the source, reads the duration, sets
`_loaded = true` and then applies the remembered speed — all inside one `try`
whose `catch` resets the state and throws `AudioUnavailable`. A backend that
refuses `setRate` (Media Foundation's `SetPlaybackRate` throws through
`THROW_IF_FAILED`; some Android players refuse rate changes on some streams)
therefore makes a file that loaded and can play at 1x report "Audio playback is
not available on this device". The speed is a preference, not a property of the
file, and `setSpeed` itself is written to swallow exactly this failure ("Some
files cannot change speed; they play at 1x").
**Trigger:** the person cycles to 1.5x or 2x on one voice note (`cycleSpeed`
sets `_speed`), then taps a different note: every later `load` on this player
re-applies the non-default speed. If the platform refuses it, playback of that
note — and every note after it — is refused with the wrong message. Without a
speed change `_speed` is 1, which most backends accept, so the bug needs the
speed chip to have been used.
**Evidence:** lines 157-164 put `setSource`, `duration` and `setRate` in the
same `try`; the catch at 165-168 cannot tell which one failed. `setSpeed`
(207-216) catches and returns, and `load`'s failure is terminal for that note:
`_loaded` stays false, so `play` (line 174) returns silently until another load
succeeds.
**Impact:** the person is told the device cannot play audio while it can play
the same file at 1x; until they pick a different note (and that load re-applies
the speed), the note is unusable. Silent beyond the generic sentence — nothing
links it to the speed chip that caused it.
**Fix sketch:** apply the speed in a nested `try` that ignores failure (as
`setSpeed` does), and keep the load failure for `stop`/`setSource`/`duration`
only. The nested catch can also reset `_speed` to 1 so the next load is not
poisoned by a speed this backend will refuse again.
**Test that proves it:** `FakeAudioBackend` with a `rateError`;
`await player.load('/x')` succeeds, `await player.play()` reaches the backend,
and the state reports a duration rather than `AudioUnavailable`. A second test:
`load` after a `setSpeed(2)` on a refusing backend still plays.
**Overlap:** S14e-1 below. No other finding covers the audio adapter; 14b's
`chat_platform.dart:47-50` note (one factory) resolved to one player per
`PlaybackNotifier`, disposed with it — no leak.

### AUD-14e-2 A microphone failure is swallowed, so the recording looks alive and is sent with a longer duration than its audio

**Severity:** P3  **Confidence:** likely
**Where:**
[device_voice_recorder.dart:159](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/device_voice_recorder.dart#L159)
and [:167](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/device_voice_recorder.dart#L167)
(`onError: (_) {}` on both subscriptions),
[device_voice_recorder.dart:243-253](file:///J:/Projects/helix/helix_remote/app/lib/core/platform/device_voice_recorder.dart#L243-L253)
(`_onBackendPhase` handles only paused/recording).
**What:** the `record` plugin reports a capture failure as an **error** on its
state stream (native `onCaptureFailure` calls `sink.onError`), and an ended
recording as `RecordState.stop` → `VoicePhase.idle`. `DeviceVoiceRecorder`
discards errors on both subscriptions and ignores `idle` from the backend, so
after a failure `_phase` stays `recording`: `_runningSince` is still set, the
clock in `stop()` keeps counting, and the amplitude subscription has already
stopped delivering. The composer mirrors the same phase (`_voicePhaseSub` only
records the value, `composer_notifier.dart:662-666`) and its 100 ms tick keeps
adding to `_voiceElapsedMs` while nothing is recorded.
**Trigger:** the microphone is lost in a way that ends capture instead of the
plugin's interruption path (which pauses and resumes): a device that stops the
input when another app takes it, a Bluetooth SCO teardown, the default input
unplugged on Windows. The plugin's own capture-failure path exists for exactly
these.
**Evidence:** the two `onError: (_) {}` handlers (159, 167); `_onBackendPhase`
handles `paused` and `recording` only (247-252); `_elapsed` (137-140) counts
from the wall clock whenever `_runningSince` is set, and only `_enter` clears
it; `stop()` computes `durationMs` from `_elapsed` (199) and returns the file
regardless of how long it actually grew. The composer's label and the stored
`durationMs` come from these clocks, and the bubble's label is
`formatDurationMs(first.row.durationMs)` (`media_content.dart:86`).
**Impact:** a voice note whose bubble says 2:30 holds 0:20 of audio; the
recipient's player ends early, and the sender watched a recording UI that never
moved a bar and never ended. The person's only way out is to cancel and retake.
**Fix sketch:** one end path. On a backend error or an `idle` while `_path !=
null`, bank the clock and `_enter(VoicePhase.idle)` (keeping the file so
`stop()` returns what was captured); the composer's phase listener treats `idle`
during a recording as "the recording ended" and offers to send it or drop it
with a sentence. `dispose`/`stop`/`cancel` already funnel through `_release`,
which can be the same place.
**Test that proves it:** `FakeRecordBackend.states.addError(StateError('mic'))`
mid-recording: `recorder.phases` reports idle, the clock stops (a later
`stop()` returns the duration only up to the error), and the composer's state
leaves `recording` with a notice. The existing clock tests (pause/resume, three
seconds) keep passing.
**Overlap:** none. 14b read `chat_platform.dart` and found no player leak; this
is the recorder's own state machine.

## Verified safe

- **Recorder clock** (`device_voice_recorder.dart:126-140, 255-264`): paused
  time is banked, a pause and resume of the system are followed, and an empty
  or failed start deletes its file and emits nothing. The waveform merge
  (`voice_recorder.dart:134-155`) takes the peak per bucket, floors quiet
  readings, and caps at 72 samples.
- **Recorder results** (`stop`, `cancel`): a file that does not exist or is
  empty is deleted in both spellings (the plugin's returned path and the one
  asked for) and reported as no recording; the engine's copy is deleted in
  `ComposerNotifier.endVoice`'s `finally`.
- **Video player** (`device_video_player.dart`): completion is computed as
  position reaching duration and drops `playing`; `play` re-seeks to zero after
  the end; `seek` is clamped by the plugin; `dispose` is idempotent and removes
  the listener first; `VideoSession` (cross-read) is `autoDispose`d per path, so
  leaving the page releases the decoder and audio focus, and its `_disposed`
  guard means an in-flight `initialize` cannot write to a closed notifier.
- **Audio player** (`device_audio_player.dart`): `seek` is clamped into
  `[0, duration]`; a completion resets to the start with `completed`;
  `setSpeed` tolerates refusal; a paused/failed state is reported and the
  notifier clears the current note on failure (`audio_playback.dart:141-149`).
- **`chat_platform.dart`**: each seam is a provider with a fake in tests; the
  recorder is disposed with the container; the audio player factory is called
  once per `PlaybackNotifier` and that notifier disposes it.

## Coverage notes

- Read in full: the seven files in **Where** (1,043 lines), plus the two
  consumer notifiers and the relevant plugin source in the pub cache.
- Not filed, seen and weighed: (a) `DeviceAudioPlayer.load` emits its
  duration-bearing state before `PlaybackNotifier` subscribes (the notifier
  subscribes after `load`), but the plugin sends its own duration event with
  preparation and position updates, so the value settles within a tick — a
  candidate only if a device shows an empty progress bar; (b) a failed
  `backend.stop()` still returns the partial file (`stop` at 202-218) — the
  file may lack its MP4 index, but this only happens after a stop error, which
  is already a broken recorder; (c) `UnavailableAudioPlayer`,
  `UnavailableVoiceRecorder` and `UnavailableVideoPlayers` are never
  constructed by any code — dead fallbacks kept for tests, harmless.
- `FlutterMediaProcessor`'s video path calls `NativeVideoFrameSource`; that
  class was read in 14d.
- Not read here: `orbit_ui`'s audio bubble widget (sweep 16) and the
  conversation presentation layer (sweep 15, features); the findings above are
  in `core/platform` or in the two consumer notifiers that define the seam's
  contract.

## Structural proposals

**S14e-1 — a preference that fails is not a file that fails.** Both adapters
have settings that a platform may refuse (speed, audio focus, rate on some
streams): `setSpeed` and `_configure` already swallow them, `load` does not.
One rule — load failures are the source, the duration and the stop; everything
else is best effort — applied to both adapters makes 14e-1 impossible and stops
the next setting added to `load` from repeating it.

**S14e-2 — a recording has one end.** The recorder's clock, waveform, file and
phase should all end at one place (`_end(phase)`), reached by an explicit stop,
a system stop (idle) and a capture error alike. Today `_release` is that place
for stop/cancel/dispose, while errors and idle are dropped. Funnelling all three
through it (banking the clock, keeping the file for `stop()`) gives the
composer one event to react to and makes 14e-2 a state-machine test rather than
a race.
