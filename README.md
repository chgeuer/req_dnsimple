# ReqDnsimple

[![Hex version badge](https://img.shields.io/hexpm/v/req_dnsimple.svg)](https://hex.pm/packages/req_dnsimple)

A lightweight [DNSimple](https://dnsimple.com) API v2 client for Elixir, built on [Req](https://hexdocs.pm/req).

No framework dependencies — just Req, NimbleOptions, and straightforward Elixir structs.

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

### List accounts

```elixir
accounts = ReqDnsimple.Account.list(client)
# => [%ReqDnsimple.Account{id: 12345, email: "you@example.com", ...}]
```

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

**Delete a record:**

```elixir
:ok = ReqDnsimple.ZoneRecord.delete(client, account_id, "example.com", record_id)
```

### Get a zone file

```elixir
{:ok, zone_file} = ReqDnsimple.Zone.get_zone_file(client, account_id, "example.com")
# => {:ok, "$ORIGIN example.com.\n$TTL 3600\n..."}
```

### Check zone distribution

```elixir
{:ok, true} = ReqDnsimple.Zone.check_zone_distribution(client, account_id, "example.com")
```

### Billing charges

```elixir
{:ok, charges} = ReqDnsimple.BillingCharge.list(client, account_id,
  start_date: "2024-01-01",
  end_date: "2024-12-31",
  sort: [invoiced: :desc]
)
```

### Contacts

```elixir
{:ok, contacts} = ReqDnsimple.Contact.list(client, account_id, sort: [label: :asc])
{:ok, contact}  = ReqDnsimple.Contact.get(client, account_id, contact_id)
```

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

| Module | DNSimple API | Operations |
|--------|-------------|------------|
| `ReqDnsimple` | Client, `/whoami`, apex NS record enumeration | `new_client/1`, `whoami/1`, `token_type/1`, `ns_records/3` |
| `ReqDnsimple.Account` | `/accounts` | `list/1` |
| `ReqDnsimple.Zone` | `/zones` | `list/3`, `get_zone_file/3`, `check_zone_distribution/3` |
| `ReqDnsimple.ZoneRecord` | `/zones/:zone/records` | `list/4`, `get/4`, `create/4`, `update/5`, `delete/4` |
| `ReqDnsimple.BillingCharge` | `/billing/charges` | `list/3` |
| `ReqDnsimple.Contact` | `/contacts` | `list/3`, `get/3` |
| `ReqDnsimple.NsRecord` | NS record struct | `from_json/1` |
| `ReqDnsimple.Helper` | Req utilities | `append/2` (URL/param merging) |

## Return Value Conventions

- **Account.list/1** returns `[%Account{}]` directly (no tuple wrapper)
- **Most list operations** return `{:ok, results}` or `{:ok, {results, pagination}}`
- **Single-item gets** return `{:ok, struct}` or `{:error, :not_found}`
- **Create/Update** return `{:ok, struct}` or `{:error, reason}`
- **Delete** returns `:ok` or `{:error, reason}`
- **Validation errors** return `{:error, %NimbleOptions.ValidationError{}}`
- **Generic HTTP errors** return
  `{:error, %{status: status, response: response_body}}`; endpoint-specific
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

DNSimple uses prefixed tokens. `ReqDnsimple.token_type/1` detects them:

```elixir
ReqDnsimple.token_type("dnsimple_u_abc")  # => :user_token
ReqDnsimple.token_type("dnsimple_a_abc")  # => :account_token
ReqDnsimple.token_type("other")           # => :unknown_token
```

## DNSimple API Reference

This library wraps the [DNSimple API v2](https://developer.dnsimple.com/v2/).

## License

MIT
