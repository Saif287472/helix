# features/groups

Group management screens (Phase A3a). The group *conversation* is the chats
feature's; this is everything around it. The engine does the work
(`engine.groups`, Sender Keys, roster authority on the server).

```
application/
  groups_port.dart      GroupsPort (interface) + EngineGroupsPort over GroupsService,
                        chats.setDisappearing and people; groupsPortProvider
  group_models.dart     plain values: GroupSnapshot, roles, permissions, previews, signals
  group_info.dart       GroupInfoView (members named by the naming order, owner/admins
                        first, per-member actions by role); groupInfoProvider
  group_actions.dart    every change returns GroupResult(ok, message) - a plain sentence
  group_errors.dart     exceptions/server codes -> sentences (stale, permission, privacy,
                        dead link, full group, offline)
  create_group.dart     the new-group form, member candidates, lookup by number / ~name
  group_invites.dart    invite links (memory only), join requests, bans, join-by-link flow
  group_picture.dart    encrypted group picture: upload, fetch, picker, scaling
  group_navigation.dart groupChatLocationProvider (seam), groupSignalsProvider
presentation/           create, info, settings, invite, requests, banned, add members,
                        join (preview + confirm), member picker
groups_routes.dart      /home/groups/new, /join, /:id and /settings /invite /requests
                        /banned /add under it
```

## Seams

- **Group chat location.** `groupChatLocationProvider` maps `group:<id>` to a router
  location; the composition root overrides it with the conversation route (for
  example `(id) => '/home/chat/$id'`). Until then a new group and a finished join
  open the group's info page. One override line wires it.
- **Members** are picked from the people this device knows plus a server lookup by
  phone number or `~Helix name` (no contact requests exist). A2b's search widget can
  replace `MemberPicker`'s list; its contract is `selected` / `onToggle` / `exclude`.
- Names: `core/people/name_lookup.dart` (shared with calls).

## Join by link

`https://<server>/open#HLX-GRP-...` and `helix://open?code=HLX-GRP-...` parse to
`HelixDeepLinkKind.groupLink` (code kept byte for byte: token and preview key are
case-sensitive). The router pushes `/home/groups/join` with the code as `extra`
(never in the path). The screen previews (nothing joins), then needs an explicit
Join / Ask to join. A link tapped while signed out waits in `pendingLinkProvider`
and is routed once the account is ready. The link is a secret: held in memory for
the flow, never logged or put in a notification; `InviteLinkInfo.toString` redacts.

## Behaviour worth knowing

- Roles: owner (one), admin, member. Owner: make/remove admin, make owner, remove,
  ban, delete. Admin: members only. The server enforces the same; a refusal is a
  sentence, not an exception.
- Settings: who may edit info / add members / send (admins always can).
- Disappearing messages default: `chats.setDisappearing('group:<id>')`, admins.
- Invite links: the server has no list, so links made in a session live in memory
  (share / revoke until the app closes). Approval mode makes join requests.
- Bans: the server keeps no ban list; only bans made on this device are listed.
- Federated members show their server (`uuid@domain`); a federated group shows its
  home server.
- Group picture and description are inside the encrypted group state; the picture
  is a `persistent` media object encrypted with its own key (created in the app
  layer: the engine has no standalone-image upload yet).
- Open: no QR for links, no per-member "message" shortcut, no group call.
