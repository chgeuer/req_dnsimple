# ReqDnsimple

[![Hex version badge](https://img.shields.io/hexpm/v/req_dnsimple.svg)](https://hex.pm/packages/req_dnsimple)

A lightweight [DNSimple](https://dnsimple.com) API v2 client for Elixir, built on [Req](https://hexdocs.pm/req).

No framework dependencies — just Req, NimbleOptions, and straightforward Elixir structs.

ReqDnsimple intentionally exposes a documented subset of the published DNSimple
API rather than claiming complete endpoint coverage. The versioned
[operation inventory](docs/audit/operation-inventory.json) is the source of truth
for that boundary:

- `existing` marks operations available before the API-parity campaign.
- `implemented` marks operations added and contract-tested during the campaign.
- `pending` marks approved campaign operations that are not implemented yet.
- `out-of-scope` marks published DNSimple operations deliberately excluded from
  the campaign.

The inventory records implementation and test evidence; the repository's `br`
tracker remains the authority for live campaign progress.

## Installation

```elixir
def deps do
  [
    {:req_dnsimple, github: "chgeuer/req_dnsimple"}
  ]
end
```

## Quick Start

### Create a client

```elixir
client = ReqDnsimple.new_client("dnsimple_u_your_token_here")
```

You can also pass a zero-arity function for dynamic token resolution. The
function is evaluated for each request and may return either the token string or
`{:bearer, token}`:

```elixir
client = ReqDnsimple.new_client(fn ->
  System.fetch_env!("DNSIMPLE_TOKEN")
end)
```

### Identify yourself

```elixir
{:user, user} = ReqDnsimple.whoami(client)
# => {:user, %{"id" => 12345, "email" => "you@example.com", ...}}
```

`whoami/1` selects `{:user, user}` or `{:account, account}` from the non-null
identity in the successful response, independently of token spelling or the
client's authentication configuration. If both identities are present or both
are absent, it returns `{:unknown_token, full_response_body}`.

### List accounts

```elixir
accounts = ReqDnsimple.Account.list(client)
# => [%ReqDnsimple.Account{id: 12345, email: "you@example.com", name: "Example Team", ...}]
```

`Account.name` is optional because older responses may omit it. DNSimple's
account examples and official SDK include the field even though its OpenAPI
schema does not.

### List zones

```elixir
{:ok, zones} = ReqDnsimple.Zone.list(client, account_id)
# => {:ok, [%ReqDnsimple.Zone{name: "example.com", ...}, ...]}
```

Filter and sort:

```elixir
{:ok, zones} = ReqDnsimple.Zone.list(client, account_id,
  name_like: "example",
  sort: [:id, name: :asc]
)
```

Use `list_page/3` when pagination metadata is needed, or `list_all/3` to fetch
every page from page one:

```elixir
{:ok, {zones, pagination}} = ReqDnsimple.Zone.list_page(client, account_id, per_page: 50)
{:ok, all_zones} = ReqDnsimple.Zone.list_all(client, account_id, name_like: "example")
```

`Contact` and `BillingCharge` provide the same `list_page/3` and `list_all/3`
interfaces. `ZoneRecord` provides `list_page/4` and `list_all/4`. `list_all`
preserves filters, sorting, and `per_page`, but rejects `page` because complete
enumeration always begins at page one.

### Manage DNS records

**List records for a zone:**

```elixir
{:ok, {records, pagination}} = ReqDnsimple.ZoneRecord.list(
  client, account_id, "example.com",
  type: "A",
  sort: [:id, name: :asc]
)
```

**Create a record:**

```elixir
{:ok, record} = ReqDnsimple.ZoneRecord.create(
  client, account_id, "example.com",
  name: "www", type: "A", content: "93.184.215.14", ttl: 3600
)
```

**Update a record:**

```elixir
{:ok, record} = ReqDnsimple.ZoneRecord.update(
  client, account_id, "example.com", record_id,
  content: "93.184.215.15", ttl: 1800
)
```

`ttl` and `priority` accept non-negative integers. Explicit zero values are
sent unchanged; omitted fields remain absent from the request.
For create and update, `integrated_zones` accepts integer zone IDs and the
literal `"dnsimple"` target, for example `[1, 2, "dnsimple"]`. Omitting the
option lets the API propagate the mutation to its default targets; an explicit
list, including an empty list, is sent unchanged. The endpoint documentation
and examples support `"dnsimple"` even though the OpenAPI item schema currently
declares integers only.

**Apply an atomic batch:**

```elixir
{:ok, %ReqDnsimple.ZoneRecord.BatchResult{} = result} =
  ReqDnsimple.ZoneRecord.batch_change(client, account_id, "example.com",
    creates: [[name: "", type: "A", content: "192.0.2.1"]],
    updates: [[id: record_id, ttl: 0, regions: []]],
    deletes: [[id: obsolete_record_id]]
  )
```

Batch changes are sent in one non-retried request. DNSimple processes deletes,
then updates, then creates, while preserving operation order within each list.
Each list is optional; explicitly empty lists are sent unchanged.

**Delete a record:**

```elixir
:ok = ReqDnsimple.ZoneRecord.delete(client, account_id, "example.com", record_id)
```

### Update hosted-zone NS records

```elixir
{:ok, ns_records} =
  ReqDnsimple.Zone.update_ns_records(client, account_id, "example.com",
    ns_names: ["ns1.example.com", "ns2.example.com"],
    ns_set_ids: [name_server_set_id]
  )
```

Pass `ns_names`, `ns_set_ids`, or both; explicit empty lists are sent unchanged.
The call replaces apex NS records in one request without first reading or
merging existing records. To retain vanity name-server configuration, include
its names or sets in the call. This hosted-zone operation does not change the
domain's registrar delegation.

### Get a zone file

```elixir
{:ok, zone_file} = ReqDnsimple.Zone.get_zone_file(client, account_id, "example.com")
# => {:ok, "$ORIGIN example.com.\n$TTL 3600\n..."}
```

### Check zone distribution

```elixir
{:ok, true} = ReqDnsimple.Zone.check_zone_distribution(client, account_id, "example.com")
```

### Check zone record distribution

```elixir
{:ok, false} =
  ReqDnsimple.ZoneRecord.check_distribution(client, account_id, "example.com", record_id)
```

### Billing charges

```elixir
{:ok, charges} = ReqDnsimple.BillingCharge.list(client, account_id,
  start_date: "2024-01-01",
  end_date: "2024-12-31",
  sort: [invoiced: :desc]
)
```

Billing amounts are returned as exact decimal strings, including trailing zeroes.
Callers that need arithmetic should parse them explicitly with their chosen
arbitrary-precision decimal library.

### Contacts

```elixir
{:ok, contacts} = ReqDnsimple.Contact.list(client, account_id, sort: [label: :asc])
{:ok, contact}  = ReqDnsimple.Contact.get(client, account_id, contact_id)
:ok = ReqDnsimple.Contact.delete(client, account_id, contact_id)
```

### Domains

```elixir
{:ok, domain} = ReqDnsimple.Domain.get(client, account_id, "example.com")
```

Domain retrieval accepts a name or integer ID and returns registration state,
privacy, renewal, and nullable expiry metadata in a typed
`ReqDnsimple.Domain` struct.

### Registrar operations

Check a domain before registration or transfer:

```elixir
{:ok, %ReqDnsimple.Registrar.CheckResult{} = result} =
  ReqDnsimple.Registrar.check(client, account_id, "example.com")
```

The registrar check is intended for low-volume interactive use and has a
stricter rate limit than most DNSimple endpoints. It reports availability,
premium status, and the optional trustee flag without using the paid Domain
Research API, registering the domain, or retrying a rate-limited request.

Enable or disable future automatic renewal without renewing or otherwise
modifying the domain:

```elixir
:ok = ReqDnsimple.Registrar.enable_auto_renewal(client, account_id, "example.com")
:ok = ReqDnsimple.Registrar.disable_auto_renewal(client, account_id, "example.com")
```

Both operations accept a domain name or integer ID, send one bodyless request,
and return registry or TLD refusal responses as explicit errors.

Enable WHOIS privacy without a price lookup or purchase preflight:

```elixir
{:ok, %ReqDnsimple.Registrar.WhoisPrivacy{} = privacy} =
  ReqDnsimple.Registrar.enable_whois_privacy(client, account_id, "example.com")
```

The operation accepts a domain name or integer ID and returns the typed privacy
state for modern HTTP 200 and legacy HTTP 201 responses. It sends one bodyless
request and does not promise or initiate a separate one-year purchase. Legacy
payment failures, including HTTP 402, are returned as explicit errors.

Submit a renewal without a price lookup or follow-up polling:

```elixir
{:ok, %ReqDnsimple.Registrar.Renewal{} = renewal} =
  ReqDnsimple.Registrar.renew(
    client,
    account_id,
    "example.com",
    period: 2,
    premium_price: "20.00"
  )
```

The period is optional and otherwise selected by the TLD. A supplied premium
price remains an exact string. Both immediate and asynchronous responses return
the typed renewal job and preserve its state.

Submit an expired-domain restore without a price lookup or eligibility preflight:

```elixir
{:ok, %ReqDnsimple.Registrar.Restore{} = restore} =
  ReqDnsimple.Registrar.restore(
    client,
    account_id,
    "example.com",
    premium_price: "109.00"
  )
```

The premium price is optional and remains an exact string when supplied. Both
immediate and asynchronous responses return the typed restore job. DNSimple
determines restore charges and eligibility; payment and registry refusals are
returned as explicit errors without an automatic renewal, purchase, or poll.

```elixir
{:ok, name_servers} =
  ReqDnsimple.Registrar.change_delegation(
    client,
    account_id,
    "example.com",
    name_servers: ["ns1.example.com", "ns2.example.com"]
  )
```

Delegation changes accept a domain name or integer ID and replace the registrar
name-server list in one request. The supplied order and explicit empty lists are
preserved; the wrapper does not fetch or merge the old delegation. This is
separate from hosted-zone apex NS records and `Zone.update_ns_records/4`.

### Domain Research

```elixir
{:ok, research} =
  ReqDnsimple.DomainResearch.get_status(client, account_id, domain: "example.com")
```

Domain Research is a paid service requiring the `domain_research_read` OAuth
scope. It returns the request ID, researched domain, availability
(`"available"`, `"unavailable"`, or `"unknown"`), and any research errors in a
typed `ReqDnsimple.DomainResearch` struct. It uses the dedicated research
endpoint, does not fall back to a registrar availability check, and does not
automatically retry quota responses.

### Domain pushes

```elixir
:ok = ReqDnsimple.DomainPush.accept(client, account_id, push_id, contact_id: contact_id)
:ok = ReqDnsimple.DomainPush.reject(client, account_id, push_id)
```

Accepting a push sends exactly one request using the selected target-account
contact. Rejecting a push sends a bodyless request and does not delete the source
domain. Neither operation performs a preflight request.

### DNSSEC

```elixir
{:ok, dnssec} = ReqDnsimple.Dnssec.get(client, account_id, "example.com")
:ok = ReqDnsimple.Dnssec.disable(client, account_id, "example.com")
```

Retrieval returns the enabled and active states separately, with typed creation
and update timestamps.

For hosted-only domains, remove registry delegation-signer records before
disabling DNSSEC. This operation does not remove those records or prompt for
confirmation.

### Delegation-signer records

```elixir
{:ok, delegation_signer_record} =
  ReqDnsimple.DelegationSignerRecord.get(
    client,
    account_id,
    "example.com",
    ds_record_id
  )

:ok =
  ReqDnsimple.DelegationSignerRecord.delete(
    client,
    account_id,
    "example.com",
    ds_record_id
  )
```

Retrieval returns a typed `ReqDnsimple.DelegationSignerRecord`; DS and KEY proof
fields that do not apply to the returned representation are `nil`.
Deletion removes only the selected registry delegation-signer record. It does
not disable DNSSEC or delete hosted-zone records.

### Email forwards

```elixir
{:ok, email_forward} =
  ReqDnsimple.EmailForward.get(client, account_id, "example.com", email_forward_id)

:ok = ReqDnsimple.EmailForward.delete(client, account_id, "example.com", email_forward_id)
```

Retrieval returns a typed `ReqDnsimple.EmailForward` with its full alias email,
destination email, activation state, and timestamps. The returned `alias_email`
is distinct from the local-part `alias_name` used when creating a forward.
Deletion removes only the selected email forward. It does not send mail or
modify the domain's MX records.

### Secondary-DNS primary servers

```elixir
{:ok, primary_server} = ReqDnsimple.PrimaryServer.get(client, account_id, primary_server_id)
:ok = ReqDnsimple.PrimaryServer.delete(client, account_id, primary_server_id)
```

The returned `ReqDnsimple.PrimaryServer` includes its IP, integer port, and the
ordered list of linked secondary-zone names. Retrieval makes no zone-transfer
or reachability requests. Deletion removes only the selected primary-server
configuration; it does not unlink zones or perform DNS requests.

## Convenience Delegates

The top-level `ReqDnsimple` module provides shorthand delegates for common operations:

```elixir
# These are equivalent:
ReqDnsimple.list_zones(client, account_id)
ReqDnsimple.Zone.list(client, account_id)

ReqDnsimple.create_zone_record(client, account_id, "example.com", attrs)
ReqDnsimple.ZoneRecord.create(client, account_id, "example.com", attrs)
```

`ReqDnsimple.ns_records/3` is a read-only convenience for enumerating every
apex (`name=""`) NS record in a zone through the zone-record collection. These
records describe the zone apex; they are distinct from registrar delegation and
from the separate API that explicitly replaces a zone's NS records.

## API Modules

This catalog describes the currently exported modules and operations; it is not
a claim that every published DNSimple endpoint is wrapped.

| Module | DNSimple API | Operations |
|--------|-------------|------------|
| `ReqDnsimple` | Client, `/whoami`, apex NS record enumeration | `new_client/1`, `whoami/1`, `token_type/1`, `ns_records/3` |
| `ReqDnsimple.Account` | `/accounts` | `list/1` |
| `ReqDnsimple.Zone` | `/zones` | `list/3`, `update_ns_records/4`, `get_zone_file/3`, `check_zone_distribution/3` |
| `ReqDnsimple.ZoneRecord` | `/zones/:zone/records`, `/zones/:zone/batch` | `list/4`, `get/4`, `create/4`, `update/5`, `delete/4`, `check_distribution/4`, `batch_change/4` |
| `ReqDnsimple.BillingCharge` | `/billing/charges` | `list/3` |
| `ReqDnsimple.Contact` | `/contacts` | `list/3`, `get/3`, `delete/3` |
| `ReqDnsimple.Domain` | `/domains/:domain` | `get/3`, `delete/3` |
| `ReqDnsimple.DomainResearch` | `/domains/research/status` | `get_status/3` |
| `ReqDnsimple.DelegationSignerRecord` | `/domains/:domain/ds_records/:ds_record` | `get/4`, `delete/4` |
| `ReqDnsimple.EmailForward` | `/domains/:domain/email_forwards/:email_forward` | `get/4`, `delete/4` |
| `ReqDnsimple.DomainPush` | `/pushes/:push` | `accept/4`, `reject/3` |
| `ReqDnsimple.Registrar` | `/registrar/domains/:domain` | `check/3`, `authorize_transfer_out/3`, `disable_auto_renewal/3`, `enable_auto_renewal/3`, `enable_whois_privacy/3`, `renew/3`, `renew/4`, `restore/3`, `restore/4`, `change_delegation/4` |
| `ReqDnsimple.PrimaryServer` | `/secondary_dns/primaries/:primary_server` | `get/3`, `delete/3`, `from_json/1` |
| `ReqDnsimple.NsRecord` | NS record struct | `from_json/1` |
| `ReqDnsimple.Helper` | Req utilities | `append/2` (URL/param merging) |

## Return Value Conventions

- Response timestamps are parsed as `DateTime` values and normalized to UTC,
  including valid ISO 8601 timestamps with nonzero offsets.
- **Account.list/1** returns `[%Account{}]` directly (no tuple wrapper)
- **Most list operations** return `{:ok, results}` or `{:ok, {results, pagination}}`
- **Single-item gets** return `{:ok, struct}` or `{:error, :not_found}`
- **Create/Update** return `{:ok, struct}` or `{:error, reason}`
- **Delete** returns `:ok` or `{:error, reason}`
- **Validation errors** return `{:error, %NimbleOptions.ValidationError{}}`
- **Generic HTTP errors** return
  `{:error, %{status: status, response: response_body}}`; responses with a
  `Retry-After` header also include `retry_after: value`. Endpoint-specific
  errors such as `:not_found`, `:unauthorized`, and `:timeout` remain atoms

## Sorting and Filtering

List operations accept keyword options validated by NimbleOptions:

```elixir
# Sort ascending by name
ReqDnsimple.Zone.list(client, account_id, sort: [name: :asc])

# Sort descending, multiple fields
ReqDnsimple.ZoneRecord.list(client, account_id, "example.com",
  sort: [type: :asc, name: :desc]
)

# Filter by name pattern
ReqDnsimple.ZoneRecord.list(client, account_id, "example.com",
  name_like: "www",
  type: "A"
)

# Pagination
ReqDnsimple.Zone.list(client, account_id, page: 2, per_page: 50)
```

## Token Types

DNSimple uses prefixed tokens. `ReqDnsimple.token_type/1` inspects those prefixes
as a standalone utility; `whoami/1` determines identity from the API response:

```elixir
ReqDnsimple.token_type("dnsimple_u_abc")  # => :user_token
ReqDnsimple.token_type("dnsimple_a_abc")  # => :account_token
ReqDnsimple.token_type("other")           # => :unknown_token
```

## DNSimple API Reference

This library wraps the [DNSimple API v2](https://developer.dnsimple.com/v2/).

## License

MIT
