# Rules for working with ReqDnsimple

## Overview

ReqDnsimple is a lightweight DNSimple API v2 client for Elixir built on Req.
It provides typed structs and validated options for all DNSimple API operations.
No framework dependencies — just `req` and `nimble_options`.

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
| `Contact.list/3` | `{:ok, [%Contact{}, ...]}` | `{:error, reason}` |
| `Contact.get/3` | `{:ok, %Contact{}}` | `{:error, :not_found}` |
| `BillingCharge.list/3` | `{:ok, [%BillingCharge{}, ...]}` | `{:error, reason}` |
| `Zone.get_zone_file/3` | `{:ok, binary()}` | `{:error, reason}` |
| `Zone.check_zone_distribution/3` | `{:ok, boolean()}` | `{:error, reason}` |

Note that `Account.list/1` returns a bare list, not an `{:ok, list}` tuple.
For `Zone`, `Contact`, and `BillingCharge`, `list_page/3` returns
`{:ok, {items, pagination}}` and `list_all/3` returns every item as
`{:ok, items}`. `ZoneRecord` provides the corresponding `list_page/4` and
`list_all/4` interfaces. Every `list_all` starts at page one, preserves other
filters and pagination size, and rejects an explicit `page` option.
Ordinary HTTP failures return
`{:error, %{status: status, response: response_body}}`. Existing
endpoint-specific mappings such as `:not_found`, `:unauthorized`, and `:timeout`
take precedence.

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
```

### Typical Account Discovery Flow

```elixir
client = ReqDnsimple.new_client(token)
[account | _] = ReqDnsimple.Account.list(client)
{:ok, zones} = ReqDnsimple.Zone.list(client, account.id)
{:ok, {records, _pagination}} = ReqDnsimple.ZoneRecord.list(client, account.id, "example.com")
```

## Module Reference

- `ReqDnsimple` — Client creation (`new_client/1`), `whoami/1`, `token_type/1`,
  `ns_records/3`, convenience delegates, and `from_json/3` for JSON→struct conversion.
- `ReqDnsimple.Account` — Account listing. Struct: `id`, `email`, `plan_identifier`,
  `created_at`, `updated_at`.
- `ReqDnsimple.Zone` — Zone listing, zone file retrieval, distribution checks.
  Struct: `id`, `account_id`, `name`, `active`, `reverse`, `secondary`, timestamps.
- `ReqDnsimple.ZoneRecord` — Full CRUD for DNS records. Struct: `id`, `zone_id`,
  `name`, `content`, `ttl`, `priority`, `type`, `regions`, `parent_id`,
  `system_record`, timestamps.
- `ReqDnsimple.BillingCharge` — Billing charge listing with date range filters.
  Contains nested `ReqDnsimple.BillingCharge.Item` structs.
- `ReqDnsimple.Contact` — Contact listing and retrieval. 14 contact fields + timestamps.
- `ReqDnsimple.NsRecord` — Name server record struct and JSON parsing.
- `ReqDnsimple.Helper` — Req helper for incrementally appending URL path segments
  and merging params/path_params onto a `Req.Request`.

## Important Notes

- All API functions take a `Req.Request` client as the first argument
- Account ID is required for most operations (obtained from `Account.list/1`)
- Zone operations accept zone names (e.g., `"example.com"`) as identifiers
- Options are validated at call time via NimbleOptions — invalid options return
  `{:error, %NimbleOptions.ValidationError{}}`
- The `create` and `update` functions for ZoneRecord take keyword lists, not maps
- `from_json/3` is a shared utility for converting DNSimple JSON responses to Elixir structs
