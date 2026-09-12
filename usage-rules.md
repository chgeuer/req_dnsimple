# Rules for working with ReqDnsimple

## Overview

ReqDnsimple is a lightweight DNSimple API v2 client for Elixir built on Req.
It provides typed structs and validated options for its documented subset of
DNSimple API operations.
No framework dependencies — just `req` and `nimble_options`.

## API Coverage

Use the versioned
[operation inventory](docs/audit/operation-inventory.json) to determine whether
an operation is part of the library's supported surface:

- `existing` marks operations available before the API-parity campaign.
- `implemented` marks operations added and contract-tested during the campaign.
- `pending` marks approved campaign operations that are not implemented yet.
- `out-of-scope` marks published DNSimple operations deliberately excluded from
  the campaign.

The inventory describes the bounded implementation target and its evidence, not
live issue state. The repository's `br` tracker is the authority for campaign
progress. An operation absent from the inventory is not implicitly supported.

## Client Creation

Always start by creating a client with `ReqDnsimple.new_client/1`:

```elixir
# Static token
client = ReqDnsimple.new_client("dnsimple_u_your_token")

# Dynamic token (zero-arity function returning a token string or {:bearer, token})
client = ReqDnsimple.new_client(fn -> System.fetch_env!("DNSIMPLE_TOKEN") end)
```

Dynamic token functions are evaluated lazily for every request. The client is a
`Req.Request` struct pre-configured with the DNSimple base URL and auth. Pass it
as the first argument to every API call.

## Return Value Patterns

Different modules use slightly different return conventions:

| Module | Success | Failure |
|--------|---------|---------|
| `Account.list/1` | `[%Account{}, ...]` | `{:error, reason}` |
| `Zone.list/3` | `{:ok, [%Zone{}, ...]}` | `{:error, reason}` |
| `ZoneRecord.list/4` | `{:ok, {[%ZoneRecord{}, ...], pagination}}` | `{:error, reason}` |
| `ZoneRecord.create/4` | `{:ok, %ZoneRecord{}}` | `{:error, reason}` |
| `ZoneRecord.update/5` | `{:ok, %ZoneRecord{}}` | `{:error, reason}` |
| `ZoneRecord.delete/4` | `:ok` | `{:error, reason}` |
| `ZoneRecord.get/4` | `{:ok, %ZoneRecord{}}` | `{:error, :not_found}` |
| `ZoneRecord.check_distribution/4` | `{:ok, boolean()}` | `{:error, reason}` |
| `ZoneRecord.batch_change/4` | `{:ok, %ZoneRecord.BatchResult{}}` | `{:error, reason}` |
| `Contact.list/3` | `{:ok, [%Contact{}, ...]}` | `{:error, reason}` |
| `Contact.get/3` | `{:ok, %Contact{}}` | `{:error, :not_found}` |
| `Contact.delete/3` | `:ok` | `{:error, reason}` |
| `Domain.get/3` | `{:ok, %Domain{}}` | `{:error, reason}` |
| `DomainResearch.get_status/3` | `{:ok, %DomainResearch{}}` | `{:error, reason}` |
| `Dnssec.get/3` | `{:ok, %Dnssec{}}` | `{:error, reason}` |
| `Dnssec.disable/3` | `:ok` | `{:error, reason}` |
| `DelegationSignerRecord.get/4` | `{:ok, %DelegationSignerRecord{}}` | `{:error, reason}` |
| `DelegationSignerRecord.delete/4` | `:ok` | `{:error, reason}` |
| `EmailForward.get/4` | `{:ok, %EmailForward{}}` | `{:error, reason}` |
| `EmailForward.delete/4` | `:ok` | `{:error, reason}` |
| `DomainPush.accept/4` | `:ok` | `{:error, reason}` |
| `DomainPush.reject/3` | `:ok` | `{:error, reason}` |
| `BillingCharge.list/3` | `{:ok, [%BillingCharge{}, ...]}` | `{:error, reason}` |
| `Zone.get_zone_file/3` | `{:ok, binary()}` | `{:error, reason}` |
| `Zone.check_zone_distribution/3` | `{:ok, boolean()}` | `{:error, reason}` |
| `Zone.update_ns_records/4` | `{:ok, [%ZoneRecord{}, ...]}` | `{:error, reason}` |

`whoami/1` returns `{:user, user}` or `{:account, account}` according to the
single non-null identity in the successful response, regardless of token prefix
or custom Req authentication. If both identities are present or absent, it
preserves the complete response body in `{:unknown_token, body}`.

Note that `Account.list/1` returns a bare list, not an `{:ok, list}` tuple.
For `Zone`, `Contact`, and `BillingCharge`, `list_page/3` returns
`{:ok, {items, pagination}}` and `list_all/3` returns every item as
`{:ok, items}`. `ZoneRecord` provides the corresponding `list_page/4` and
`list_all/4` interfaces. Every `list_all` starts at page one, preserves other
filters and pagination size, and rejects an explicit `page` option.
Ordinary HTTP failures return
`{:error, %{status: status, response: response_body}}`. Existing
endpoint-specific mappings such as `:not_found`, `:unauthorized`, and `:timeout`
take precedence. If a response includes `Retry-After`, the generic error map
also includes `retry_after: value`.

## Common Patterns

### Listing with Filters, Sorting, and Pagination

Most list operations accept keyword options validated by NimbleOptions:

```elixir
# Filtering
ReqDnsimple.Zone.list(client, account_id, name_like: "example")
ReqDnsimple.ZoneRecord.list(client, account_id, zone, name: "www", type: "A")

# Sorting (bare fields default to :asc; tuples accept :asc/:desc)
ReqDnsimple.Zone.list(client, account_id, sort: [name: :desc])
ReqDnsimple.ZoneRecord.list(client, account_id, zone, sort: [:type, name: :desc])

# Pagination
ReqDnsimple.Zone.list(client, account_id, page: 2, per_page: 50)
```

Sort options are lists like `[:id, name: :desc]`. Supported fields are endpoint-specific:
zones accept `:id` and `:name`; records accept `:id`, `:name`, `:content`, and `:type`;
contacts accept `:id`, `:label`, and `:email`; billing charges accept only `:invoiced`.
They are automatically converted to DNSimple's `"name:asc,id:desc"` string format
by `ReqDnsimple.convert_sort_to_string/1`.

### CRUD Operations on Zone Records

```elixir
# Create — attrs is a keyword list, name/type/content are required
{:ok, record} = ReqDnsimple.ZoneRecord.create(client, account_id, "example.com",
  name: "www", type: "A", content: "93.184.215.14", ttl: 3600
)

# Read
{:ok, record} = ReqDnsimple.ZoneRecord.get(client, account_id, "example.com", record_id)

# Update — only pass the fields you want to change
{:ok, record} = ReqDnsimple.ZoneRecord.update(client, account_id, "example.com", record_id,
  content: "93.184.215.15"
)

# Delete
:ok = ReqDnsimple.ZoneRecord.delete(client, account_id, "example.com", record_id)

# Check distribution
{:ok, distributed?} =
  ReqDnsimple.ZoneRecord.check_distribution(client, account_id, "example.com", record_id)

# Atomic batch; each operation list is optional
{:ok, %ReqDnsimple.ZoneRecord.BatchResult{} = result} =
  ReqDnsimple.ZoneRecord.batch_change(client, account_id, "example.com",
    creates: [[name: "", type: "A", content: "192.0.2.1"]],
    updates: [[id: record_id, ttl: 0, regions: []]],
    deletes: [[id: obsolete_record_id]]
  )
```

Record `ttl` and `priority` values are non-negative integers. Explicit zero
values are transmitted unchanged, while omitted fields remain omitted.
Both create and update accept `integrated_zones: [integer() | "dnsimple"]`.
Omitting the option preserves the API's default target propagation, while an
explicit list (including `[]`) is transmitted unchanged. The published endpoint
prose and examples support the `"dnsimple"` sentinel despite the OpenAPI item's
integer-only declaration.
Batch changes never include `integrated_zones`, never change a record's type,
and are sent as one non-retried request. DNSimple processes deletes, updates,
and creates in that order while retaining the caller's order within each list.

### Typical Account Discovery Flow

```elixir
client = ReqDnsimple.new_client(token)
[account | _] = ReqDnsimple.Account.list(client)
{:ok, zones} = ReqDnsimple.Zone.list(client, account.id)
{:ok, {records, _pagination}} = ReqDnsimple.ZoneRecord.list(client, account.id, "example.com")
```

### Reading Apex Name Server Records

`ReqDnsimple.ns_records/3` reads all apex NS records by listing zone records
with exact `name=""` and `type="NS"` filters. It is read-only and returns a bare
list of `ReqDnsimple.NsRecord` structs. Apex zone records are separate from the
domain's registrar delegation. `Zone.update_ns_records/4` explicitly replaces
the hosted zone's apex NS records from `ns_names`, `ns_set_ids`, or both. It
preserves explicit empty lists and performs no lookup or merge, so callers
retaining vanity configuration must include those names or sets themselves.
The update does not change registrar delegation.

## Module Reference

- `ReqDnsimple` — Client creation (`new_client/1`), response-based identity
  discovery (`whoami/1`), token-prefix inspection (`token_type/1`),
  `ns_records/3`, convenience delegates, and `from_json/3` for JSON→struct conversion.
- `ReqDnsimple.Account` — Account listing. Struct: `id`, `email`, optional `name`,
  `plan_identifier`, `created_at`, `updated_at`. DNSimple's examples and official
  SDK include `name` even though its OpenAPI schema omits it.
- `ReqDnsimple.Zone` — Zone listing, apex NS updates, zone file retrieval, and
  distribution checks.
  Struct: `id`, `account_id`, `name`, `active`, `reverse`, `secondary`, timestamps.
  `last_transferred_at` is `nil` when a zone has not been transferred.
- `ReqDnsimple.ZoneRecord` — Full CRUD, distribution checks, and atomic batch changes for DNS records.
  Record struct: `id`, `zone_id`,
  `name`, `content`, `ttl`, `priority`, `type`, `regions`, `parent_id`,
  `system_record`, timestamps. Batch responses use `ZoneRecord.BatchResult` and
  `ZoneRecord.DeletedRecord`.
- `ReqDnsimple.BillingCharge` — Billing charge listing with date range filters.
  Contains nested `ReqDnsimple.BillingCharge.Item` structs. Monetary values remain
  exact decimal strings; parse them explicitly with an arbitrary-precision decimal
  library when arithmetic is required. Manual-charge item product identifiers and
  references may be `nil`.
- `ReqDnsimple.Contact` — Contact listing and retrieval. 14 contact fields + timestamps.
- `ReqDnsimple.Domain` — Retrieval and explicit deletion by name or ID.
  Retrieval returns registration state, privacy, renewal, and nullable expiry
  metadata. Deletion is irreversible within the account, but does not delete a
  registration at the registry or produce a refund.
- `ReqDnsimple.DomainResearch` — Paid domain-availability research through the
  dedicated endpoint. Requires the `domain_research_read` OAuth scope and
  returns request ID, domain, availability, and research errors without falling
  back to a registrar availability check.
- `ReqDnsimple.Dnssec` — Typed DNSSEC status retrieval and explicit disablement
  by domain name or ID. Retrieval keeps enabled and active as separate states
  and parses creation/update timestamps. For hosted-only domains, registry
  delegation-signer records must be removed first; disablement does not remove
  them or prompt for confirmation.
- `ReqDnsimple.DelegationSignerRecord` — Typed retrieval and explicit deletion
  of one registry delegation-signer record by domain name or ID and record ID.
  DS and KEY proof fields that do not apply are `nil`. Deletion does not disable
  DNSSEC or delete hosted-zone records.
- `ReqDnsimple.EmailForward` — Typed retrieval and explicit deletion of one
  domain email forward by domain name or ID and forward ID. Retrieval preserves
  the full alias email, destination, activation state, and timestamps. Deletion
  does not send mail or modify MX records.
- `ReqDnsimple.DomainPush` — Accept a pending push with an explicit target-account
  contact, or reject it without deleting the source domain.
- `ReqDnsimple.Registrar` — Explicitly authorize transfer-out by domain name.
  DNSimple unlocks the domain and emails the authorization code to its
  administrative contact; the wrapper performs no follow-up request.
- `ReqDnsimple.PrimaryServer` — Secondary-DNS primary server retrieval and
  explicit deletion. Struct: `id`, `account_id`, `name`, `ip`, integer `port`,
  ordered `linked_secondary_zones`, and timestamps. Deletion does not unlink
  zones or perform DNS requests.
- `ReqDnsimple.NsRecord` — Name server record struct and JSON parsing.
- `ReqDnsimple.Helper` — Req helper for incrementally appending URL path segments
  and merging params/path_params onto a `Req.Request`.

## Important Notes

- All API functions take a `Req.Request` client as the first argument
- Account ID is required for most operations (obtained from `Account.list/1`)
- Zone operations accept zone names (e.g., `"example.com"`) as identifiers;
  `Zone.update_ns_records/4` also accepts a numeric zone ID
- Options are validated at call time via NimbleOptions — invalid options return
  `{:error, %NimbleOptions.ValidationError{}}`
- The `create` and `update` functions for ZoneRecord take keyword lists, not maps
- `from_json/3` is a shared utility for converting DNSimple JSON responses to Elixir structs
- Valid ISO 8601 response timestamps, including nonzero offsets, are normalized
  to UTC `DateTime` values; missing and null timestamps remain `nil`
