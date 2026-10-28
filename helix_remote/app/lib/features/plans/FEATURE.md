# plans (ADR-035)

You > **Orbit Premium**: what the plan adds, what it costs and how to pay. Plans
are off until the operator switches on the flag `billing_enabled`; while they are
off the You page draws no Orbit Premium row and the page says plans are not open.

A payment is made outside the app, in bKash or Nagad. The page shows the numbers
the operator set, the app sends only the **transaction ID**, and the operator
approves it by hand in Orbit Console. The page then shows Pending, the reason of
a rejection, or Premium until a date. Nothing is deleted when Premium ends.

| Piece | Where |
|---|---|
| Page | `presentation/premium_page.dart`, drawn from the kit's rows, notices and fields (`orbit.OrbitYouPage`, `OrbitSection`, `OrbitListRow`, `OrbitTextField`, `OrbitButton`) |
| What the page draws | `application/plan_models.dart` (`PlanView`, plain values; presentation never sees a protocol type) |
| Data | `application/plans_gateway.dart` (`PlansGateway`; `ApiPlansGateway` is the only thing that touches `api.billing`), `application/plans_providers.dart` (`billingPlanProvider`, `premiumLabelProvider` for the You row, `planPurchaseProvider`) |
| Route | `plans_routes.dart`, `RoutePaths.premium` |
| You row | `orbit_ui`'s `YouModel.premiumLabel` (null hides it), `YouTopic.premium`, wired in `shared/widgets/orbit_you_connector.dart` |

## Rules this feature keeps

- The server decides the plan; the app only shows it. Nothing here unlocks a
  limit.
- The transaction ID is checked on the phone (`BillingLimits.normalizeTrxId`)
  before it is sent, and the server checks it again.
- Failures are sentences (`describeFailure`, plus the plan's own conflicts: a
  request already waiting, an ID already used); no exception text reaches the
  screen.
- No prototype screen exists for this page; it is built from existing kit
  components (recorded in `orbit/DEVIATIONS.md`).

## Also here (Phase 2)

- **The trial.** A new account's first week reads "You are on the free trial" with its end date; the You row
  says "Free trial until …".
- **Pack locks.** While plans are on and the account is Free, `billingPlanProvider` sets
  `packsLockedProvider` (core). A downloadable theme or ringtone cannot be fetched, updated or chosen (its
  row reads "Orbit Premium · …", and the action answers with that sentence); a downloaded theme is not drawn
  (`orbitTokensProvider` falls back to Orbit and keeps the choice); a downloaded ringtone choice is cleared and
  the phone's own sound returns. The two built-in themes and the built-in ringtones are never locked, and
  nothing is locked while plans are off or the plan cannot be read.
- **The wake-up.** A `plan` push wakes the phone; the background handler shows one quiet notification ("Your
  plan request was updated.", no account, amount or ID) and stops. In front, `pushWakeTickProvider` makes the
  plan page and the You row read the plan again.

## Not built yet (see `docs/product/ORBIT_PREMIUM_PLAN.md`)

Call time (Phase 3).
