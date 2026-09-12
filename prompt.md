# ReqDnsimple API parity: one-issue worker

This is an existing, approved implementation campaign, not a request to start a
new audit or campaign. All scope, compatibility, execution, and verification
decisions below were approved by the maintainer. State lives in the repository's
`br` tracker. Take exactly one ready, non-epic issue to Done, then stop.

ReqDnsimple is a lightweight Elixir DNSimple API-v2 client built on Req and
NimbleOptions. Never weaken authentication, TLS verification, request correctness,
or exact monetary values to make a test pass.

## Mission and scope

Implement one issue labeled `api-parity`, using its acceptance criteria and Agent
Brief as the contract. Every issue is an independently complete behavior:
validated inputs, correct HTTP request, typed response, explicit errors, tests,
and directly related documentation.

The approved scope is:

- The 13 reported correctness/documentation findings.
- The 81 API operations missing relative to the audited CLI, including OAuth.
- Batch record changes, explicit zone NS updates, and seven secondary-DNS APIs.
- A final verification gate over the complete approved surface.

The baseline contains 13 existing documented REST operations. With the 90 scoped
new operations, the target is 103 distinct documented operations, not every API
in the published schema. Eight other published operations are explicitly outside
this campaign. Do not silently expand scope.

Findings are hypotheses: confirm the selected issue against current source.
An already-satisfied issue needs concrete source and executable evidence, not a
cosmetic change. An incomplete CLI implementation is not evidence that a
documented API feature should be skipped.

## Read first

- `docs/audit/README.md`: scope, epic membership, baseline, and progress queries.
- `docs/audit/api-parity.md`: the approved findings and API operation inventory.
- `docs/audit/operation-inventory.json`: implementation/evidence mapping, not a
  substitute for tracker status.
- The selected issue's full description and `br comments <id>`.
- Current `README.md`, `usage-rules.md`, and the directly relevant implementation.

Read only the selected finding/operation sections in long documents and the
inventory. Do not dump the full backlog or all API contracts into each run.

The public OpenAPI source is
`https://developer.dnsimple.com/v2/openapi.yml`. A local reference snapshot is
available at `.campaign/reference/dnsimple-openapi.yml` when the controller has
downloaded it. Its approved baseline SHA256 is
`426c0bd65e729b743e66c07036cc4e142de6c1a927c63f4290bf6595402d0b6f`.
Public API documentation is read-only reference material; production and sandbox
API hosts must never be called during this campaign.

The official CLI baseline is commit `6cb5fc5` with `dnsimple-go/v9 v9.1.1`.
The checkout at `/home/chgeuer/github/dnsimple/cli` is read-only reference material,
not a second worktree or implementation target. Do not assume its flags expose
every supported API input, and do not repeat the whole-repository audit.

## Elixir navigation

Use `/home/chgeuer/github/pnezis/probex/probex` for every `.ex` and `.exs` file,
including dependencies:

- Run `outline` the first time you inspect a file.
- Use `body` for complete functions and `preamble` before adding tests.
- Use `clauses` when a selector is ambiguous, and `directives` for name origins.
- Feed compiler/test line numbers directly into `body <file> L<n>`.
- Batch files/selectors; use the tool's `--head` or `--tail` for long blocks,
  rather than guessed line windows.
- If the executable is unavailable, confirm with `command -v probex`, report it,
  and read the file normally. Do not guess another executable path. Exit 2 is a
  selector/parse error: read the diagnostic and retry appropriately.

## Compatibility and API conventions

- Preserve existing successful public return shapes. In particular,
  `Account.list/1` and `ns_records/3` return bare lists; legacy zone/contact/billing
  lists return `{:ok, items}`; `ZoneRecord.list/4` returns
  `{:ok, {items, pagination}}`; record deletion returns `:ok`.
- Fixing previously crashing HTTP errors and response-based identity selection is
  intentional. Preserve existing documented specific error mappings and the
  established generic status/response error map.
- Legacy paginated collections gain explicit `list_page` and `list_all`
  interfaces. New paginated lists use `{:ok, {items, pagination}}`, plus deliberate
  complete enumeration. Non-paginated collections must not invent pagination.
- `list_all` begins at page one, rejects an explicit `page` option, keeps other
  supported filters/sorting/page-size options, and never returns partial success
  after an error or malformed/non-progressing pagination.
- Follow the existing singular resource-module style and the selected issue's
  proposed interfaces. The first argument is the caller's `Req.Request`; retain
  its adapter, auth, base URL, and other configured behavior.
- Honor omitted versus explicitly supplied fields, including empty apex names,
  empty lists where supported, false booleans, and numeric zero.
- Monetary strings stay exact strings. Do not implicitly convert them to floats
  or introduce a Decimal dependency to change the approved representation.
- Use proper structs/types, bounded field whitelists, and existing parsing helpers.
  Never turn arbitrary server-supplied keys into new atoms.
- A library mutation is a wrapper for an explicitly invoked API operation, not an
  interactive CLI flow. Do not introduce confirmation prompts, hidden preflight
  requests, purchases, or mutations beyond the caller's selected operation.
- Reuse existing helpers and patterns; do not add frameworks, generators,
  metaprogramming, or tooling merely to reduce local typing.

## Environment and baseline

The repository already has its Mix dependencies. Baseline commit `41eb6f9` passes:

```sh
mix compile --warnings-as-errors
mix test
mix format --check-formatted
```

The baseline suite contains two sort-formatting doctests, not API coverage.
Each implementation issue must add meaningful regression or request-contract
coverage. Dependencies currently produce some compiler/deprecation warnings on
Elixir 1.20.4; these are a recorded baseline, not permission to introduce new
project warnings or alter dependencies indiscriminately.

Tests use offline Req adapters and fake credentials. CORE-002 establishes a
test-suite default that fails closed for unmocked requests; retain that guard.
Disable retry delays in deterministic response fixtures where appropriate.
Never look for real tokens, load secret files, run a live sandbox smoke test, or
issue requests to production API hosts.

Install/restore dependencies only after an intentional manifest change or a
validation command identifies missing dependencies. Do not upgrade packages or
install lint/type-check tools just to make this campaign different.

## Selecting and claiming one issue

Before claiming, confirm the branch is `campaign/api-parity`, there is no other
active claim, and there are no unexplained source changes.

```sh
git status --short
git branch --show-current
br list --status in_progress --limit 0
br ready -l api-parity --limit 0
```

Select only an open, non-epic, `ready-for-agent` issue with all true execution
prerequisites satisfied. Work in tiers: ready CORE correctness issues first,
then ready API issues, then VERIFY-001. Within a tier prefer the highest priority
(lowest number), then related ready resource work. Container epics are membership
only, never work items or execution prerequisites.

```sh
br show <id>
br comments <id>
br update <id> --claim
```

Claim atomically before editing. A resumed run continues its already-selected
issue; it must not choose a second issue. The maintainer has approved the batch
triage and AFK implementation. Do not restart triage or ask for already-settled
policy decisions.

## One issue end to end

1. Read the complete issue and Agent Brief. Confirm the gap against current code.
2. Add a focused regression or wire-contract test and demonstrate the expected
   failure before implementation. Record the command and relevant failure.
3. Implement the smallest complete behavior, using established shared helpers.
   Include supported query/body fields, response models, error handling, and
   directly related documentation.
4. For an API issue, update only its entry in the versioned operation inventory
   with actual exported interfaces and concrete contract-test locations. Never
   mark a peer API implemented merely because its module now exists.
5. Satisfy every Definition of Done gate below. A symbol/export check or an
   inventory flag is not proof of a working HTTP contract.
6. Commit explicit files only, including the relevant tracker state. Use a
   conventional message referencing the selected br ID and finding ID.
7. Close only the selected issue with the implementation commit, what changed,
   and regression evidence. Flush and commit the resulting tracker change.
8. Write the handoff and stop immediately. Do not start another issue.

If a selected finding is already satisfied or genuinely incorrect, comment with
concrete evidence and the relevant successful test before using a `wontfix`
closure. Do not force a meaningless change. A scoped operation that remains
unimplemented, missing test coverage, an inconvenient contract, or a CLI omission
is not a false positive.

Every newly posted tracker description/comment must start with:

```markdown
> *This was generated by AI during triage.*
```

Retain exactly one category label (`bug` or `enhancement`) and one triage-state
label. Ready work uses `ready-for-agent`. A justified false-positive closure uses
`wontfix` instead. Do not remove campaign or track labels.

## Definition of Done

All gates are required before closure:

- A regression or contract test demonstrably fails before and passes after.
- Offline success cases assert actual HTTP method, fully rendered path, query
  and body fields, and the promised typed/enveloped response.
- Relevant invalid-input, HTTP error, transport error, omission/zero/null, and
  pagination cases pass without live network access or silent partial success.
- Run the focused tests for the change, then:

```sh
mix compile --warnings-as-errors
mix test
mix format --check-formatted
git diff --check
```

- Existing behavior stays compatible and directly related docs/types are updated.
- No new project warnings, test failures, unexpected source changes, or secrets.
- No unrelated or broad formatting/refactoring changes.

Do not dismiss a failure as pre-existing or flaky. Establish the actual cause.
If it cannot be resolved within this issue without broadening scope, record the
evidence and stop with the selected claim intact for controller review. Do not
close over a red suite or silently add new campaign work.

## Commits and tracker persistence

Never use `git add -A`, `git add .`, amend, force-push, destructive checkout/reset,
or automatic release/publishing commands. Stage exact named files.

Include `Copilot-Session: <your headless session UUID>` in commit messages.
Do not add any `Co-authored-by` trailer; the maintainer explicitly declined them.
Keep all commits local on `campaign/api-parity`; do not push.

```sh
br sync --flush-only
git add -- <explicit changed files> .beads/issues.jsonl
git commit
br close <id> -r "Resolved in <implementation hash>. <behavior>. Regression: <test and result>."
br sync --flush-only
git add -- .beads/issues.jsonl
git commit
```

Use non-interactive commit messages in the actual commands. Tracker close records
belong in a separate commit because they refer to the already-created
implementation commit.

## Stop conditions and handoff

Stop after exactly one closure, or when blocked. On a genuine blocker, leave a
clear tracker comment and the selected claim intact; do not hide it by changing
status to deferred/blocked, removing labels, or closing it as done.

Do not close, reopen, claim, or otherwise mutate peer issues or any epic. Do not
create another campaign, schedule, factory, or parallel implementation writer.
The controller owns supervision, resumption, broader scope decisions, and epic
closure.

End your response with both headings:

## Session summary

Name the selected br/finding IDs, behavior implemented, implementation and tracker
commit hashes, fail-before/pass-after evidence, all gate results, and any blocker.

## Next-agent prompt

Identify the next plausible ready issue as a hint, note shared interfaces changed
and any important adjacent concerns, then stop. The next worker must reconfirm
readiness from `br`, not trust this hint as state.

## Progress queries

```sh
br list -l api-parity --all --limit 0
br ready -l api-parity --limit 0
br list -l api-parity --status in_progress --limit 0
br epic status
```

The controller declares completion only after all approved non-epic issues are
closed with evidence, VERIFY-001 passes, and every track is reconciled against
its referenced issues. It closes the container epics separately. Reaching a
driver iteration limit or seeing no ready issue is not proof of completion.
