# API parity campaign

Campaign epic: **bd-ogb**. Label: `api-parity`.
Scope and execution policy were approved on 2026-09-12.

This campaign fixes 13 existing contract/documentation findings, adds 90
missing operations, and finishes with one independent verification gate.
The target is 103 documented operations: 13 existing plus 90 additions.
Eight other published operations are explicitly outside this campaign.

Counts below describe scope, not live status. `br` is the only progress
authority; a process exit, an iteration cap, or zero ready items is not
proof that implementation is complete.

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
