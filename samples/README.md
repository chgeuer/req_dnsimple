# Runnable samples

Run these examples from the repository root with `mix run samples/<name>.exs`.
They use the project and its existing dependencies; the `.exs` files do not
install dependencies. Each file is a separate program, not a step in a sequence.
[`support/setup.exs`](support/setup.exs) only shares environment validation and
client setup.

**Start with [DNSimple sandbox](https://developer.dnsimple.com/sandbox/).**
Every command-line sample defaults to `https://api.sandbox.dnsimple.com/v2`.
Sandbox tokens and account IDs are separate from production credentials.
Read-only examples still make real API requests when you run them.

## Setup and environment

Supply `DNSIMPLE_TOKEN` through your secret manager or shell environment; do not
put a real token in a script, notebook, terminal command history, or source
control. The scripts print counts, zone names, or selected account/record IDs,
never clients, credentials, record contents, or certificate private keys.

| Variable | Used by | Meaning |
| --- | --- | --- |
| `DNSIMPLE_TOKEN` | All scripts | Token string; an account token or user token as noted below. |
| `DNSIMPLE_ACCOUNT_ID` | Scoped reads, records, user discovery, dynamic credentials, record lifecycle | Explicit positive account ID. An all-digit positive string is accepted; it is not a user ID. |
| `DNSIMPLE_ZONE` | Basic reads, records, dynamic credentials | Existing zone name supplied by you; no default. |
| `DNSIMPLE_BASE_URL` | All scripts, optional | Defaults to the sandbox API URL above. Override for production or a trusted API-compatible reverse proxy, including `/v2`. A proxy receives the bearer token: use HTTPS and only infrastructure you trust. |
| `DNSIMPLE_RECORD_NAME_LIKE` | Records, optional | Substring filter; defaults to `www`. An empty value requests no name restriction from DNSimple. |
| `DNSIMPLE_RECORD_TYPE` | Records, optional | Record type filter; defaults to `A`. |
| `DNSIMPLE_ACCOUNT_IDS` | Multiple accounts | Comma-separated positive IDs of at least two distinct accounts explicitly selected by you. |
| `DNSIMPLE_ALLOW_MUTATIONS` | Record lifecycle only | Must be exactly `true`; otherwise the script fails **before any HTTP request**. |
| `DNSIMPLE_TEST_ZONE` | Record lifecycle only | Existing disposable test zone supplied explicitly; never falls back to `DNSIMPLE_ZONE`. |

For the scoped read examples, after supplying a token securely:

```sh
export DNSIMPLE_ACCOUNT_ID="YOUR_SANDBOX_ACCOUNT_ID"
export DNSIMPLE_ZONE="YOUR_SANDBOX_ZONE"
mix run samples/basic_reads.exs
```

Replace the uppercase placeholders with your own sandbox inputs. No constructor
discovers an account or checks credentials. Both account-token (`dnsimple_a_`)
and user-token (`dnsimple_u_`) scoped clients require `account_id`.

## Read-only programs

| Program | Command | What it demonstrates |
| --- | --- | --- |
| [Basic scoped reads](basic_reads.exs) | `mix run samples/basic_reads.exs` | Root `list_zones!` with options, `Zone.get` with `unwrap!`, and metadata-bearing apex `ns_records` enumeration. Needs token, account ID, and zone. |
| [Filtered record pages](records.exs) | `mix run samples/records.exs` | `ZoneRecord.list_page` versus explicit `list_all`, preserving filters, ordered sorting, and page size. Needs token, account ID, and zone. |
| [Account-token discovery](discover_account.exs) | `mix run samples/discover_account.exs` | Explicit unscoped client → `whoami` → `{:ok, {{:account, %{"id" => id}}, metadata}}` → `for_account`. Needs an account token; no account-ID environment variable is required. |
| [User-token discovery](discover_user.exs) | `mix run samples/discover_user.exs` | Explicit unscoped client → `{:ok, {accounts, metadata}}` from `Account.list` → your selected account → `for_account`. Needs a user token and `DNSIMPLE_ACCOUNT_ID`; without the ID it first prints available IDs, then fails with setup guidance. |
| [Multiple accounts](multiple_accounts.exs) | `mix run samples/multiple_accounts.exs` | Independent immutable clients sharing one user token and transport, with a local missing-scope check on the unchanged discovery client. Needs a user token and `DNSIMPLE_ACCOUNT_IDS`. |
| [Dynamic credentials and proxy](dynamic_credentials.exs) | `mix run samples/dynamic_credentials.exs` | Lazy callback returning `{:bearer, token}`, custom constructor transport options, `Req.merge`, and two requests that each resolve credentials. Needs token, account ID, and zone; optionally set `DNSIMPLE_BASE_URL`. |

Discovery never chooses the first returned account. User selection is explicit,
and a `whoami` user ID is **not** an account ID. Token prefixes are guidance, not
proof of identity or permissions. `for_account/2` performs no HTTP or permission
check; DNSimple remains the authority when an operation is sent.

Dynamic credentials must continue to authorize the selected account after
rotation. The callback is not evaluated at construction or re-scoping time.
Do not inspect a client or call `token_type(client)` during setup: the latter
evaluates a dynamic callback. The example uses an API-compatible **reverse**
proxy via `base_url`, not an HTTP CONNECT/forward-proxy configuration.

Every HTTP operation returns `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
`{:error, %ReqDnsimple.Error{}}`, including non-paginated account lists, tagged
identities, and mutations. HTTP 204/bodyless successes have `nil` data.
`ReqDnsimple.Response.result(data)` is the common type; `Response` is a
formatter, not a returned struct. Named bang helpers exist only for zone
listing and strip only `:ok`, returning `{data, metadata}`. `unwrap!/1` works
the same way for every HTTP operation, including `Account.list`, `ns_records`,
and `whoami`. The samples explicitly destructure `_metadata` where they do
not need it.

Prefer `list_page` for page-oriented code and `list_all` when you deliberately
want every page. Both expose metadata; read the nested string-keyed pagination
map as `metadata.pagination`. Complete enumeration always starts at page one,
rejects `page:`, and retains each response's metadata under `metadata.pages`
in request order, including empty/single-page collections. Aggregate budget,
Retry-After, and parse-error fields reflect the last page; top-level status,
pagination, request ID, and ETag are `nil`, not synthetic collection values.

Optional response metadata fields may be `nil`; malformed headers or body
pagination are reported in `parse_errors` instead of failing valid resource
data. Rate-limit reset is non-negative integer Unix seconds. Request IDs,
ETags (including quotes and weak prefixes), and Retry-After (delay or HTTP-date)
are opaque strings. Metadata adds no automatic rate limiting, retries, or
caching, and retains no raw response headers or bodies wholesale.

`ReqDnsimple.Error` retains the original `reason` and optional `metadata`.
Generic HTTP error reasons retain status/body; Retry-After lives in metadata.
Local validation and transport failures have no HTTP metadata of their own.
Later enumeration failures retain received pages; an HTTP failure also retains
the failing response, while a transport failure never fabricates one. Bang
failures raise that structured error without stripping metadata.
The pure `OAuth.authorize_url/2,3` helper is unchanged: `{:ok, url}` or
`{:error, %NimbleOptions.ValidationError{}}`. Constructors still return
`Req.Request` and raise `ArgumentError` on invalid configuration.

## Opt-in mutation: one record lifecycle

**Use DNSimple sandbox and a disposable zone.** The
[record lifecycle](record_lifecycle.exs) creates a uniquely named TXT record,
updates that record, and deletes **only the ID returned by its own create
request**. It never searches for a record to delete and never modifies
delegation, existing records, registrations, or certificates.

With a sandbox token and account ID already configured:

```sh
DNSIMPLE_ALLOW_MUTATIONS=true \
DNSIMPLE_TEST_ZONE="YOUR_DISPOSABLE_SANDBOX_ZONE" \
mix run samples/record_lifecycle.exs
```

Replace the zone placeholder; the script does not create a zone. Missing consent
or a missing test zone fails before a client is used. Automatic retries are
disabled in sample transport setup.

Cleanup runs even when update returns an API/transport error. The script reports
an update failure after successful cleanup, preserving the update error's
response metadata. If deletion fails, it reports the new record's ID and
retains **both** full outcomes (`operation_result` and `cleanup_result`,
including their metadata) in `ReqDnsimple.Error.reason` under
`:sample_cleanup_failed`. The outer error metadata is the cleanup error's
metadata. It never prints tokens or raw response bodies. Check that specific
record in the sandbox before rerunning. This is a sequence of requests, not an
atomic transaction: process termination, an unexpected exception, or an
ambiguous create response can leave
a record behind. If creation times out without an ID, inspect the test zone
manually; the script does not guess which record to delete.

## Livebook

Open [discover.livemd](discover.livemd) for a **read-only** notebook with scoped
clients, a trusted reverse-proxy option, explicit pagination, and dynamic token
resolution. Its setup explains all Livebook secrets and environment variables,
including the local repository path. Client setup cells end with `:ok` to avoid
displaying bearer credentials.

See the [main guide](../README.md#quick-start) and
[usage rules](../usage-rules.md#client-creation) for the full scoped and legacy
interfaces.
