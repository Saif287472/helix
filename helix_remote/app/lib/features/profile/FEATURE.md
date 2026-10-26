# profile

Your profile (Phase A3b), `/profile`: name and about line (published encrypted
through `PeopleService.setOwnProfile`), your `~Helix name`, your picture, and
your masked phone number. Each field says who can see it.

The editor draws `orbit_ui`'s `ProfileEditScreen` through
`presentation/profile_page.dart`: the same fields on one screen, a live preview
of your orbit, and one Save that sends the name, about line and `~name` in
order, with each field's own refusal. "Who sees what" follows ADR-030 (the
operator sees the name and the number).

- **Name / about**: one encrypted profile, published together. Limits 50 / 139
  characters (`ProfileRules`).
- **~Helix name**: normalised (`~Anna.K` -> `anna.k`) and checked against the
  server's pattern before sending. The server answers a taken name and a name
  that could pass for Orbit staff (admin, support, official, helix ...) the same
  way on purpose; the page explains both in one sentence.
- **Picture**: chosen with `ProfileImageSource` (gallery; centre-square crop,
  256 px PNG, done off the screen's code) and kept on this phone
  (`ProfileAvatarStore`). Choosing it also **shares it** (Part B E1): the
  engine encrypts the picture into a persistent media object and puts its
  pointer in the sealed profile, so only the people you message can open it —
  the server and its operator see ciphertext. Because the profile is one
  encrypted object, the name and about line already saved go out with it;
  unsaved edits stay unsaved. Removing it takes the shared picture back and
  deletes that object. A share that fails (no network) leaves the picture on
  this phone and says so; the person can retry. A camera capture needs a
  camera plugin and is not offered.
