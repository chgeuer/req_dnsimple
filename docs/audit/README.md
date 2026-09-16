# API parity campaign

Campaign epic: **bd-ogb**. Label: `api-parity`.
Scope and execution policy were approved on 2026-09-12.

The historical campaign scope comprised 13 existing contract/documentation
findings, 90 missing operations, and one independent verification gate.
Its target was 103 documented operations: 13 existing plus 90 additions.
Eight other published operations were explicitly outside that campaign.

The separately approved official Elixir SDK-parity extension on 2026-09-15
adds seven of those operations. The current inventory therefore covers 110
supported operations, including all 99 endpoints in DNSimple Elixir SDK
v10.0.0 and 11 additional endpoints. Only `getDomainRestore` remains excluded.
The campaign counts and tracker memberships below retain their original scope;
the extension does not retrospectively add campaign issues.

Counts below describe scope, not live status. `br` is the only progress
authority; a process exit, an iteration cap, or zero ready items is not
proof that implementation is complete.

## Current HTTP result contract

The separately approved breaking result contract applies uniformly to all 110
supported operations: `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
`{:error, %ReqDnsimple.Error{reason: original_reason, metadata: metadata}}`.
HTTP 204/bodyless successes have `nil` data; account listing and tagged
`whoami` identities are no longer bare results. Bang helpers strip only `:ok`.
`ReqDnsimple.Response.result(data)` is the shared type/formatter, not a returned
struct.

Single-response metadata retains status, nested string-keyed
`metadata.pagination`, rate-limit fields, request ID, opaque ETag and
Retry-After strings, and explicit `parse_errors` for malformed optional metadata.
Missing optional values are `nil`; rate-limit reset is integer Unix seconds.
Complete enumeration, including `ns_records`, returns aggregate metadata with
each page in request order under `.pages`, even for empty or single-page
collections. Aggregate budgets, Retry-After, and parse errors reflect the last
page; aggregate status, pagination, request ID, and ETag remain `nil`.
Later failures retain received page metadata without fabricating a transport
response. This adds no automatic rate limiting, retries, or caching and retains
no raw headers or bodies wholesale in metadata.

Pure `OAuth.authorize_url/2,3` remains `{:ok, url}` or
`{:error, %NimbleOptions.ValidationError{}}`; only token exchange performs HTTP.
Local HTTP-operation validation/transport errors are structured `ReqDnsimple.Error`
values with no response metadata of their own; constructors still raise
`ArgumentError`.

Inventory schema version 2 records metadata-bearing response types and replaces
the old pagination-tuple flag with explicit metadata/pagination-location flags.
Endpoint paths, operation IDs, provenance, arities, and historical tracker scope
are unchanged: 111 published operations, only `getDomainRestore` excluded,
102 account-path operations, and 144 scoped interface families. See the
[current result guide](../../README.md#return-value-conventions), not historical
success-preservation requirements, when consuming SDK results.

## Tracks

| Epic | Track | Non-epic issues |
|---|---|---:|
| bd-27c | Existing API correctness and compatible contracts | 13 |
| bd-4po | Zones, records, and secondary DNS | 13 |
| bd-2xv | Contact mutations | 3 |
| bd-63x | Domains, DNSSEC, DS records, email, pushes, and research | 20 |
| bd-178 | Domain registrar operations | 20 |
| bd-39o | Certificate lifecycle | 8 |
| bd-3i3 | Reusable DNS services | 5 |
| bd-25b | Templates and template records | 10 |
| bd-1ax | TLD metadata | 3 |
| bd-1ku | Vanity nameservers | 2 |
| bd-2uv | Webhook management | 4 |
| bd-1y0 | DNS analytics | 1 |
| bd-3tc | OAuth token exchange | 1 |
| bd-1gp | Final contract and coverage verification | 1 |

## Tracker membership and dependencies

The installed br version permits ready children under open parent epics.
Only genuine implementation prerequisites use `blocks` edges.
The controller, not an implementation worker, closes container epics.

## References

- [Findings and scoped operation list](api-parity.md)
- [Machine-readable operation inventory](operation-inventory.json)
- [Worker workflow and Definition of Done](../../prompt.md)
- [Campaign configuration](../../.campaign.conf)

Baseline: req_dnsimple `41eb6f9`; official CLI `6cb5fc5`; dnsimple-go `v9.1.1`.
Public OpenAPI: https://developer.dnsimple.com/v2/openapi.yml
Reference SHA256: `426c0bd65e729b743e66c07036cc4e142de6c1a927c63f4290bf6595402d0b6f`.
The complete downloaded reference is a local, ignored campaign artifact.
The SDK-parity extension also uses `dnsimple/dnsimple-elixir` v10.0.0 at
`16fc5fb` as a reference, with its implementation evidence recorded in the
current operation inventory.

## Verification baseline

`mix compile --warnings-as-errors`, `mix test`, and
`mix format --check-formatted` passed before campaign implementation.
The original suite has two sort doctests, not HTTP contract coverage.
Existing dependencies emit some warnings under Elixir 1.20.4; no new
project warnings or test failures are allowed. Use offline Req adapters
and fake credentials only, never a live DNSimple account.

## Progress and resumption

```sh
br list -l api-parity --all --limit 0
br ready -l api-parity --limit 0
br list -l api-parity --status in_progress --limit 0
./campaign.sh --dry-run
./campaign.sh
```

Run one driver at a time on `campaign/api-parity`. It stops on dirty
tracked source, a residual claim, a failed/timed-out run, or an invalid
one-issue transition. Inspect its log and pinned session before resuming.
All commits remain local; do not push or add Co-authored-by trailers.
