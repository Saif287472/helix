EarnMinute Codebase Architecture Report — Findings
Repository root: e:\Saif\earnminute (git repo, most recent commit ccd219a — "Full codebase structure refactor and module system introduce, Attachments in chatting system", 2026‑04‑09).

1. Overall folder/module structure
   Top level is a classic split-monorepo with no root README.md but with a set of plain-text "AI-context" documents instead (unusual and notable — see §8):

e:\Saif\earnminute\
├── backend/ Node/Express API
├── frontend/ React (Vite) SPA
├── scripts/ extract-module.js, verify-account-settings.mjs
├── Project_Details.txt Full architecture/conventions doc (721 lines)
├── EarnMinute_Overview.txt Product overview
├── MASTER_PRODUCTION_CHECKLIST.txt
├── MODULE_backend_settings.txt / MODULE_frontend_settings.txt (generated AI context packs)
├── extract-backend.js / extract-frontend.js / extract-insights.js / extract-target.js
Both backend/ and frontend/src/ follow a "modular monolith, feature-first" layout (explicitly named this way in Project_Details.txt line 59 and 109). Each side has a modules/ directory that is the canonical home for business logic, sitting alongside older controllers/routes/services directories that are now kept only as thin backward-compatible shims (evidence of a deliberate, incremental migration rather than a rewrite-and-pray approach).

Backend (backend/, 201 tracked files, excluding node_modules):

backend/
├── server.js thin bootstrap (382 lines) — mounts modules, sockets, middleware
├── config/validateEnv.js startup env-var crash guard
├── modules/ CANONICAL business logic, one folder per feature:
│ admin/ applications/ auth/ chat/ disputes/ feedback/
│ notifications/ payments/ settings/ tasks/ users/
├── domain/ pure state-machine/permission logic (no I/O)
│ task/ (taskStates.js, taskTransitions.js, taskPermissions.js, taskValidator.js)
│ escrowStates.js, escrowTransitions.js, escrowValidator.js
│ paymentProviderState*.js
├── repositories/ one file per Mongoose model — all DB queries live here
├── models/ Mongoose schemas only
├── middleware/ authMiddleware, banMiddleware, csrfProtection, validate, errorMiddleware, abuseLimiter
├── validations/ shared Zod schemas (paramValidation.js, actionValidation.js)
├── services/ shared/legacy services + payment/ subfolder + guards/ subfolder
├── events/ AppEvents.js (domain event bus), eventTypes.js
├── utils/ AppError.js, asyncHandler.js, errorCodes.js, logger.js
├── routes/, controllers/ LEGACY — kept only as shims to modules/ for backward compat
└── *.test.js (12 files) node:test suite at repo root
Frontend (frontend/src/, 135 files):

frontend/src/
├── App.jsx thin lazy-loaded route registry only
├── main.jsx
├── modules/ feature modules mirroring the backend 1:1 (api/, index.js, MODULE.md)
│ admin/ applications/ auth/ chat/ disputes/ feedback/
│ notifications/ payments/ settings/ tasks/ users/
├── pages/ route-level screens, grouped by role/domain (auth/, employer/, freelancer/, admin/, public/, chat/, payment/, settings/, legal/, misc/)
├── components/ shared presentational components (ui/, tasks/, chat/, admin/, dispute/, profile/)
├── hooks/ incl. hooks/admin/ subfolder
├── context/ AuthContext.jsx
├── services/ api.js (axios+CSRF), socket.js, chatService.js, etc.
├── utils/ taskStates.js, taskActionEngine.js, queryKeys.js, logger.js
├── i18n/, locales/en+bn i18next
The backend modules/_ and frontend modules/_ directory names are symmetric (auth, tasks, chat, payments, disputes, feedback, notifications, settings, users, admin, applications), so an engineer or AI agent working on a feature knows exactly where to look on both sides without searching.

2. Separation of concerns (layering)
   Each backend module follows the same 4-layer pattern, documented per-module in MODULE.md files (e.g. backend/modules/tasks/MODULE.md):

<name>Routes.js → Express router / wiring only
<name>Controller.js → HTTP handlers (req/res), thin
<name>Service.js → business logic (source of truth)
<name>Validation.js → Zod schemas (when module-specific)
index.js → public entrypoint (barrel export)
MODULE.md → purpose, owned files, route table, dependencies, notes
Below that, cross-cutting concerns are pulled into their own single-purpose layers:

repositories/ – one file per model, e.g. backend/repositories/taskRepository.js — all Mongoose queries isolated from business logic (createTask, getAllOpenTasks, findExpiredOpenTasks, searchTasks, all under 60 lines shown).
domain/ – pure, I/O-free state-machine and permission logic (task/escrow), completely decoupled from Express or Mongoose.
services/guards/taskGuard.js – tiny single-purpose guard (assertTaskNotDisputed, 18 lines) reused across services instead of duplicating the same if check.
middleware/ – auth, ban, CSRF, validation, rate limiting, and the global error handler each in their own file.
events/AppEvents.js – a domain event bus decoupling notification/side-effect fan-out from core service logic.
server.js itself is explicitly "thinned to pure bootstrap" (per Project_Details.txt line 110/424): it only sets up middleware, mounts module routers (app.use("/api/v1/tasks", tasksModule.router)), wires Socket.IO, and starts background jobs — no business logic at all.

3. Error handling — unified/centralized format
   This is one of the strongest structural features, built in "Stabilization Phase 1" (commit 5692940, "env validation + unified error format").

backend/utils/AppError.js (26 lines) — a single custom error class used everywhere:

class AppError extends Error {
constructor(message, statusCode = 500, details = {}) {
super(message);
this.statusCode = statusCode;
this.isOperational = true;
this.details = details;
this.code = null;
this.status = `${statusCode}`.startsWith("4") ? "fail" : "error";
Error.captureStackTrace(this, this.constructor);
}
withCode(code) { this.code = code; return this; } // chainable
}
backend/utils/errorCodes.js — a frozen, machine-readable ERROR_CODES enum (TASK_INVALID_STATE, ESCROW_NOT_FUNDED, ALREADY_APPLIED, EMAIL_ALREADY_REGISTERED, etc.) plus a codeFromStatus() fallback mapper, explicitly so "the frontend uses these to make decisions without parsing message strings" (file header comment).

backend/middleware/errorMiddleware.js (74 lines) — a single centralized Express error handler mounted once (server.js line 351/357) that normalizes every error type into one JSON shape:

Mongoose CastError → 400 BAD_REQUEST
Mongoose duplicate key (11000) → 409 with context-aware codes (EMAIL_ALREADY_REGISTERED, ALREADY_APPLIED, CONFLICT)
Mongoose ValidationError → 400 VALIDATION_ERROR
Zod issues[0].message → 400 VALIDATION_ERROR
Fallback: error.statusCode || 500, error.code || codeFromStatus(statusCode)
Response body is always { success: false, message, code, details?, stack? (dev only, 5xx only) }. This means any controller in the codebase can simply throw new AppError(...).withCode(...) or call next(err) and get identical, predictable JSON — extremely favorable for an AI agent because it never has to invent a new error shape or guess response format.

backend/utils/asyncHandler.js wraps async controllers so they don't need manual try/catch (standard Express pattern, keeps controllers short).

4. Validation patterns
   Zod is the primary validation library (backend/package.json — "zod": "^4.3.6"), used consistently via backend/middleware/validate.js (17 lines):

module.exports = (schema, target = "body") => (req, res, next) => {
try {
schema.parse(req[target] || {});
next();
} catch (err) {
return next(new AppError(err.issues?.[0]?.message || "Invalid input", 400)
.withCode(ERROR_CODES.VALIDATION_ERROR));
}
};
Applied declaratively in routers, e.g. backend/modules/tasks/tasksRoutes.js: validate(createTaskSchema).

Schemas are centralized in backend/validations/ (shared: paramValidation.js, actionValidation.js — 324 lines with things like objectId regex validator, createPublicUrlSchema with SSRF-safe URL checks, strongPassword) plus module-owned validation files (authValidation.js, disputesValidation.js, settingsValidation.js, tasksValidation.js) inside each modules/<name>/ folder.
Old backend/validations/authValidation.js, taskValidation.js, disputeValidation.js are now explicitly documented as shims redirecting to the new module-owned versions (Project_Details.txt line 137).
express-validator is still a dependency but Zod is the dominant/"audited" system — "Stabilization Phase 4: input validation audit across all routes" (commit 60de282) is documented in Project_Details.txt §21 as complete: "Zod schemas in validations/ applied consistently via validate.js middleware."
Route params validated too (idParamSchema, conversationIdParamSchema in paramValidation.js), preventing malformed ObjectId crashes. 5. State machine patterns (Task / Escrow)
Built in "Stabilization Phase 2" (commit 10c05fc, "centralized state machine for Task and Escrow"). Both follow an identical, tiny 3-file pattern:

Task — backend/domain/task/:

taskStates.js — frozen enum: DRAFT, OPEN, ASSIGNED, IN_PROGRESS, SUBMITTED, REVISION_REQUESTED, APPROVED, COMPLETED, CANCELLED, DISPUTED
taskTransitions.js — frozen adjacency map, e.g. OPEN: [ASSIGNED, CANCELLED], SUBMITTED: [APPROVED, REVISION_REQUESTED, DISPUTED]
taskPermissions.js — which role may drive each transition (ASSIGNED: ["employer"], IN_PROGRESS: ["freelancer"]...)
taskValidator.js — validateTaskTransition(currentState, nextState) throws AppError(...).withCode(TASK_INVALID_STATE) if the transition isn't in the table; assertTaskAction(task, toState, actorId, actorRole) combines transition legality + role check + ownership check in one call ("Use this in service functions instead of separate validateTaskTransition + manual auth check" — inline comment).
Escrow — backend/domain/escrowStates.js / escrowTransitions.js / escrowValidator.js:

States: PENDING, FUNDED, RELEASED, REFUNDED, DISPUTED, CANCELLED
assertEscrowTransition(currentState, nextState) — same shape as the task validator.
There's also backend/domain/paymentProviderStateMachine.js / paymentProviderStates.js / paymentProviderStateTransitions.js for the payment-provider lifecycle, following the same 3-file convention a third time — a highly predictable, copy-pasteable pattern an AI agent can generalize instantly once it has seen one instance.

Every state check in the codebase goes through these validators rather than ad-hoc if (task.status === "x") conditionals scattered through services — Project_Details.txt line 411 states explicitly: "All transitions enforced through validators, not ad-hoc conditionals."

6. Environment variable validation
   Built in "Stabilization Phase 1" (commit 5692940). backend/config/validateEnv.js (78 lines) runs once at boot, right after dotenv.config() (server.js lines 9‑10):

ALWAYS_REQUIRED array: MONGO_URI, JWT_SECRET, RESET_PASSWORD_SECRET, WEBHOOK_SECRET, CLIENT_URL, NODE_ENV, EMAIL_FROM, EMAIL_FROM_NAME
CONDITIONAL array: declarative { when: () => ..., label, vars } entries for EMAIL_PROVIDER=brevo|resend, PAYMENT_PROVIDER=sslcommerz, CHAT_ATTACHMENTS_ENABLED=true — each pulling in its own required secrets (e.g. R2 credentials only required when attachments are enabled).
On missing vars: prints a boxed, readable console error listing every missing key and calls process.exit(1) — "Crashes the process with a clear list of missing vars rather than letting it start and fail mid-request in a confusing way" (file header comment). This fails fast and loud instead of silently misbehaving in production, which is valuable both for humans and for an AI agent debugging a broken deploy.
.env.example files exist for both backend/.env.example and frontend/.env.example (added in the latest commit) documenting the exact variable names expected. 7. Naming conventions and predictability
Extremely consistent, mechanical naming across both sides:

Backend module internals: <name>Controller.js, <name>Routes.js, <name>Service.js, <name>Validation.js, index.js, MODULE.md — identical across all 11 backend modules (admin, applications, auth, chat, disputes, feedback, notifications, payments, settings, tasks, users).
Frontend module internals: api/<name>Api.js, index.js, MODULE.md (plus components/, pages/ where relevant e.g. settings).
Repositories: <Model>Repository.js 1:1 with models/<Model>.js (e.g. taskRepository.js ↔ Task.js, escrowRepository.js ↔ Escrow.js).
Domain state machines: <entity>States.js, <entity>Transitions.js, <entity>Validator.js — same triad repeated for task, escrow, and payment-provider.
Test files: <serviceName>.test.js at backend root, one per service (taskService.test.js, disputeService.test.js, chatService.test.js, paymentEscrow.test.js, authService.test.js, chatAttachmentCleanupService.test.js, etc. — 12 total).
API base route prefix is uniform: /api/v1/<module> and is documented exhaustively in Project_Details.txt §20.
Because the pattern is so rigid, an AI agent can correctly guess a file path (e.g. "the disputes service validation" → backend/modules/disputes/disputesValidation.js) without needing to search first — directly reducing tool calls and tokens spent exploring.

8. Docs describing conventions (AI-oriented)
   There is no traditional root README.md/ARCHITECTURE.md/CLAUDE.md, but the project substitutes something arguably more purpose-built for AI-agent collaboration:

Project_Details.txt (721 lines, updated 2026‑04‑08) — opens with: "This file exists so an AI assistant can build a full mental model of the project without scanning the codebase. Read everything here before suggesting changes. Keep this file updated whenever a major feature or phase is completed." It documents: tech stack, full directory layout, all Mongoose models, the task/escrow state machines, auth flow, realtime events, notification event types, security layers, all frontend routes, all backend API routes, a numbered stabilization-phase changelog (§21, phases 1–6, mapped directly to git commits), known limitations (§22), future upgrade-ready areas (§23), and even explicit development constraints for AI-assisted work (§24: "solo student, non-coder, building with Claude AI assistance... Prefer small, exact edits over broad rewrites... Never break working flows while adding new ones").
Per-module MODULE.md files (11 backend + 11 frontend, 686 total lines) — each documents Purpose, Owned Files, Service source-of-truth notes, a full Route table (method/path/auth/role), Dependencies (exact relative import paths), and gotcha Notes (e.g. backend/modules/payments/MODULE.md flags that SSLCommerz callbacks are registered in two places and why; backend/modules/tasks/MODULE.md flags that /:id must stay last in route registration).
EarnMinute_Overview.txt, MASTER_PRODUCTION_CHECKLIST.txt — additional plain-text context docs at root.
MODULE_backend_settings.txt / MODULE_frontend_settings.txt — pre-generated, ready-to-paste AI context bundles (see §9 below).
.claude/settings.local.json — the permission allowlist itself is evidence of the AI-driven workflow: entries like Bash(node --check backend/modules/tasks/tasksController.js), Bash(node --check backend/server.js) show a pattern of running Node's built-in syntax checker after every edit — a fast, cheap sanity check well suited to an agent that can't run a full test suite each time. 9. Barrel files / clean module boundaries
Every backend module has index.js as its only sanctioned export surface, e.g. backend/modules/chat/index.js:

const router = require("./chatRoutes");
const chatService = require("./chatService");
module.exports = { router, chatService };
Project*Details.txt explicitly states the rule (line 157): "Cross-module imports only via module's index.js (never deep internal paths)."
Frontend mirrors this with export * as <name>Api from "./api/<name>Api" barrels, e.g. frontend/src/modules/chat/index.js: export _ as chatApi from "./api/chatApi";
scripts/extract-module.js (222 lines) is a purpose-built CLI tool: node scripts/extract-module.js <backend|frontend|both> <module> walks only that module's directory (plus a small fixed list of shared files like AppError.js, asyncHandler.js, authMiddleware.js, api.js, AuthContext.jsx) and writes a single MODULE_<side>\_<module>.txt file "so you can paste it into an AI context window without loading the entire codebase" (file header). This is a direct, intentional token-efficiency mechanism — a human/agent can extract exactly the ~500-1000 lines relevant to one feature instead of grepping across 200+ files. Two such generated packs (MODULE_backend_settings.txt 593 lines, MODULE_frontend_settings.txt 976 lines) are already checked into the repo as examples.
frontend/vite.config.js defines a @ path alias (@: ./src), used throughout for absolute, unambiguous imports (e.g. App.jsx line 38: import("@/pages/notifications/NotificationsPage")). 10. File size discipline
No monolithic files were found. Largest files in each tree (via wc -l):

Backend (excluding node_modules, tests):

File Lines
backend/modules/chat/chatService.js 705
backend/services/payment/paymentService.js 640
backend/events/AppEvents.js 523
backend/modules/tasks/tasksService.js 519
backend/services/accessTokenService.js 476
backend/modules/disputes/disputesService.js 386
backend/server.js 381
backend/repositories/taskRepository.js 369
Frontend:

File Lines
frontend/src/components/chat/ChatWindowEnhanced.jsx 847
frontend/src/pages/admin/AdminDisputes.jsx 608
frontend/src/pages/admin/AdminUsers.jsx 552
frontend/src/pages/employer/EmployerDashboard.jsx 538
Most files (utils, domain, repositories, middleware) sit in the 10–60 line range (e.g. AppError.js 26 lines, errorCodes.js 67 lines, validate.js 17 lines, taskGuard.js 18 lines, taskStates.js/escrowStates.js ~11 lines each). Even the largest files (700–850 lines) are the "god" service/component for a genuinely complex feature (real-time chat with attachments), not accidental sprawl — and they are still an order of magnitude smaller than a typical unmodularized server.js monolith would be. This keeps the amount of context an AI agent must load to make a correct edit small and bounded.

11. Config enforcing structure
    frontend/vite.config.js — path alias (@ → src/) enforced at the bundler level, encouraging absolute imports over fragile relative ../../../ chains.
    No .eslintrc/eslint.config.\* or tsconfig.json/jsconfig.json were found anywhere outside node_modules — this is a gap (no automated lint/type enforcement); consistency currently relies on convention + documentation (MODULE.md, Project_Details.txt) rather than tooling. Worth flagging in the report as an area for a "future-proofing" recommendation.
    backend/package.json test script (node --test --test-isolation=none) and frontend/package.json (node --test --test-isolation=none, plus verify:settings running scripts/verify-account-settings.mjs) show a lightweight, dependency-free test setup using Node's built-in test runner rather than a heavy framework — fast to run, cheap for an agent to invoke.
    .gitignore at root correctly excludes .env/node_modules/dist (confirmed by commit f8fef8a "Remove .env files from tracking and add to gitignore").
12. MongoDB transactions (Phase 3) and multi-document write safety
    Confirmed present in 8+ production files (grep for startSession|withTransaction): backend/modules/chat/chatService.js, backend/modules/applications/applicationsService.js, backend/modules/disputes/disputesService.js, backend/modules/tasks/tasksService.js, backend/services/escrowService.js, backend/repositories/conversationRepository.js, backend/repositories/chatAttachmentUploadRepository.js, plus their test files. Example, backend/modules/applications/applicationsService.js around line 46:

const assignFreelancer = async (taskId, applicationId, employerId, io) => {
const session = await mongoose.startSession();
try {
session.startTransaction();
const task = await taskRepository.findById(taskId, { session });
...
This directly matches Project_Details.txt §21 Phase 3: "Critical write operations wrapped in sessions/transactions" — used anywhere a single logical action touches more than one collection (e.g. assigning a freelancer touches Task + Application; funding escrow touches Escrow + PaymentLedger).

13. Attachments/chat system (most recent commit) — modularization
    The chat-attachment feature added in ccd219a is itself cleanly modularized rather than bolted on:

Config/policy — backend/modules/chat/chatAttachmentConfig.js (310 lines): a single source of truth for ALLOWED_ATTACHMENT_TYPES (MIME→kind/size/extension map for image/document/audio/archive), MAX_FILENAME_LENGTH, MAX_ATTACHMENTS_PER_MESSAGE, READ_ONLY_TASK_STATUSES, TTLs for signed upload/download URLs, and a validateAttachmentDescriptor function — reused directly by backend/validations/actionValidation.js (imports MAX_FILENAME_LENGTH, validateAttachmentDescriptor) so the validation layer never redefines its own copy of the rules.
Model — backend/models/ChatAttachmentUpload.js (new model, 92 lines): tracks conversation, task, uploader, bucket, storageKey (unique), originalName, mimeType, size, kind enum.
New model for scale — backend/models/MessageBucket.js (134 lines, new) — a bucketed message-storage pattern layered under the existing Message model for performance.
Repository — backend/repositories/chatAttachmentUploadRepository.js (new, 89 lines) — isolates all attachment-upload DB access, following the established one-repository-per-model rule.
Storage clients — backend/services/r2Client.js (44 lines, new) and backend/services/r2Service.js (121 lines, new) wrap Cloudflare R2 (S3-compatible, via @aws-sdk/client-s3 + @aws-sdk/s3-request-presigner) behind a clean service boundary, so chatService.js never talks to AWS SDK directly.
Cleanup job — backend/services/chatAttachmentCleanupService.js (219 lines, new) — background job (startChatAttachmentCleanupJob, started from server.js line 367) that purges expired/orphaned uploads, configurable via DEFAULT_RETENTION_DAYS, DEFAULT_CLEANUP_INTERVAL_MS, DEFAULT_CLEANUP_BATCH_SIZE constants in chatAttachmentConfig.js. Has its own dedicated test file backend/chatAttachmentCleanupService.test.js (95 lines).
Env-gated — the entire feature is behind CHAT_ATTACHMENTS_ENABLED=true, and validateEnv.js only requires the R2 credentials (R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_UPLOADS, R2_ENDPOINT) conditionally when that flag is set — so the feature can be toggled off without breaking startup validation.
Frontend — mirrors the same split: frontend/src/components/chat/ChatAttachmentPicker.jsx (file-select UI, single responsibility, ~90 lines) and frontend/src/components/chat/ChatAttachmentCard.jsx (render/preview of an attached file), composed into ChatWindowEnhanced.jsx rather than that file owning upload logic directly.
Controller wiring — backend/modules/chat/chatController.js only touches attachments via three narrow concerns: attachmentIntentId on message send (line ~116-128) and an attachmentId route param (line ~175) for fetching a signed download URL — it delegates all policy/storage logic out to chatAttachmentConfig.js and r2Service.js.
This shows the same discipline applied to the newest feature as to the rest of the codebase: config/policy, model, repository, storage-client, background-job, and UI are all separate, narrowly-scoped files rather than one large "attachments.js" file.

Summary for the report
Why it's enterprise/future-proof:

Modular monolith with 1:1 symmetric module names on backend and frontend, each with routes/controller/service/validation layers plus a machine-readable MODULE.md contract (route table, deps, gotchas).
Centralized, versioned error format (AppError + ERROR_CODES + one errorMiddleware.js) normalizing Mongoose, Zod, and custom errors into one JSON shape.
Declarative, fail-fast environment validation (validateEnv.js) with conditional requirements per feature flag.
Two independently documented, symmetric finite-state machines (Task, Escrow — plus a third for payment providers) enforced through shared validators rather than scattered conditionals.
MongoDB transactions wrapped around every multi-document write.
Centralized Zod validation applied uniformly via one validate() middleware.
Legacy routes//controllers//services/ kept only as compatibility shims during the modules/ migration — evidence of safe, incremental refactoring discipline rather than risky big-bang rewrites.
Why it's safe for AI agents to work on autonomously:

Project_Details.txt is explicitly written as an AI-onboarding document ("this file exists so an AI assistant can build a full mental model... without scanning the codebase").
scripts/extract-module.js generates a single-file, module-scoped context bundle on demand.
Predictable, mechanical file naming lets an agent guess exact paths instead of searching.
.claude/settings.local.json shows an established pattern of node --check <file> after every edit as a low-cost correctness gate.
Documented "development constraints" (Project_Details.txt §24) literally instruct future contributors/agents to prefer small, exact edits and never break working flows.
Why it uses fewer tokens for AI agents:

Small, single-purpose files (most 10-60 lines; largest are 700-850 lines) mean an agent loads only what's relevant.
Barrel index.js files and the "never import module internals directly" rule bound how much of the codebase must be read to understand a dependency.
MODULE.md files let an agent understand a module's public surface without opening every internal file.
The purpose-built extraction script and pre-generated MODULE\_\*.txt context packs are literally designed to minimize what's pasted into an AI context window.
Gap worth noting: no ESLint/TSConfig or other automated structural enforcement was found (structure is currently maintained by convention and documentation, not tooling) — a natural "next step" recommendation for further future-proofing.
