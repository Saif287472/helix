# Orbit contracts (Phase 1)

A contract says what a screen needs and what it can ask for. It is the seam
between the new UI (`orbit_ui`, built in Part A) and the app's existing data
layer (`helix_remote/app/lib/features/*/application`, wired in Part B).

- **Model:** the values the screen draws. They are plain and immutable, and
  every clock or locale string arrives already formatted.
- **Actions:** the callbacks the screen calls.
- The screen never reads a provider, the database, the router or the
  engine.

Each feature has one Markdown file here. Phase 4 turns every table into Dart
exactly as written (`<Name>Model`, `<Name>Actions`, `<Name>Screen`); Part B
writes connectors that fill the model from the providers named here and route
the actions to the gateways named here. `../GAPS.md` collects every item that
needs a decision.

## Tags

Every model field and every action carries one tag:

| Tag | Meaning | Who builds it |
|---|---|---|
| **have** | The app already provides it. The source says where. | Part B connector only |
| **derive** | The app can compute it from data it already has: a filter, a count, a label. The source names the inputs. | Part B, in `application/` |
| **local** | New state kept on the device: a setting, a remembered choice. | Part B, in `application/` and local settings |
| **engine** | Needs new work in `helix_remote_engine` or `helix_remote_db`, but no server or protocol change. | Part B, using the `helix-feature` process |
| **server** | Needs server and protocol work, and usually engine work too. | Part B, using the `helix-feature` process; needs your decision |
| **demo** | Exists only to make the prototype click through (for example "Simulate a match"). | Nobody: not built |

When in doubt between two tags, pick the bigger one and say why. A field is
never tagged **have** without naming the provider, gateway method or view
model field it comes from.

## The file layout

```markdown
# Contract: <feature>

Prototype screens: `<id>` (states: `key`, `key`, …), …
Today's app: `features/<x>/presentation/…`, `features/<x>/application/…`

## <Screen title> (`<prototype id>`)

Dart: `XScreen`, `XModel`, `XActions`.

### Model
| Field | Type | Tag | Comes from today | Notes |

### Actions
| Action | Signature | Tag | Calls today | Notes |

### Kept inside the screen
What the widget keeps in its own state: open sheets, search text, scroll
position, animation. These are not part of the contract.

### Slots
| Slot | What the app puts there | What the preview shows |

### The app does this, the prototype does not show it
| What | Where in the app | Suggestion |

### New backend work
| Item | Why the design needs it | Engine / server / protocol | Size: S, M, L |
```

## Rules for writing a contract

1. **Read three things side by side.**
   - The prototype screen: `orbit/prototype/js/screens/*.js`, its section
     of `orbit/prototype/INTERACTIONS.md`, and `SCREENS.md`.
   - The app's screen today: `presentation/`.
   - The app's data layer: `application/`, plus
     `packages/helix_remote_ui/lib/src/view_models.dart`.
2. **Reuse the existing view models.**
   - When a `Helix*` view model already carries the data, use that type and
     name the fields the design adds.
   - New fields are added with defaults. Existing fields are never renamed or
     removed.
3. **Every interaction maps to an action, or is kept inside the screen.**
   Go through the screen's section of `INTERACTIONS.md` line by line.
4. **Do not assume a capability exists.**
   - If you cannot find it, tag it **engine** or **server**.
   - Say where you looked and what is missing.
5. **List what the app does that the prototype does not show:**
   - loading, empty, error and offline states;
   - permission prompts;
   - confirmations and failure messages.
   These are easy to lose in a redesign. Suggest one of three: add it to the
   design, keep today's behaviour in the new style, or drop it.
6. **Copy, in two cases:**
   - When the prototype's copy and the app's copy differ in meaning, note
     both.
   - When they differ only in style, the prototype wins.
7. **Stay in scope.**
   - Nothing under `helix_remote/` or the prototype changes in Phase 1.
   - Never read `.env` files, keystores, `docs/codebase/`, or anything listed
     in `docs/security/FORBIDDEN_FILES.md`.

## Files

| File | Covers |
|---|---|
| `frame.md` | The app frame: routes and panes on a window, the theme, overlays, the global interactions |
| `signin.md` | Sign-in, restore after sign-in, link this device, reset, app lock |
| `home.md` | Home (Chats and Calls tabs, dock, search, dial pad), Archived chats, People search |
| `conversation.md` | The conversation and its pages: forward, message info, media viewer, send files, shared media, chat settings |
| `calls.md` | The call screen and call details |
| `people_groups.md` | Contact info, safety number, scan, and every group screen |
| `you.md` | You, profile editor, Appearance, the topic pages, account pages, about, legal, advanced |
| `devices_backup.md` | Devices, link a new device, security activity, backup, restore history, send to devices, recovery backup |
