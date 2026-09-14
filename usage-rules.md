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
progress. It currently reconciles 103 supported operations (13 original and 90
added) with executable contract-test locations and records eight additional
published operations as explicitly `out-of-scope`. An operation absent from the
inventory is not implicitly supported.

The additive `scoped_interfaces` metadata covers 95 account-path operations and
137 interface families, including pagination helpers, root shortcuts, and the
existing bang functions. It records each module, function, supported arities,
and account-free arguments. The top-level `client_scope` summarizes constructors,
account selection, and the missing-scope error. Original explicit-account
interfaces and source/contract-test provenance remain intact; these overloads
do not increase the count of supported DNSimple operations.

## Client Creation

Prefer the account-scoped `ReqDnsimple.new_client/2` when the account is known:

```elixir
account_id = System.fetch_env!("DNSIMPLE_ACCOUNT_ID")

client =
  ReqDnsimple.new_client(System.fetch_env!("DNSIMPLE_TOKEN"),
    account_id: account_id
  )

# Dynamic token (zero-arity function returning a token string or {:bearer, token})
client =
  ReqDnsimple.new_client(
    fn -> {:bearer, System.fetch_env!("DNSIMPLE_TOKEN")} end,
    account_id: account_id,
    base_url: "https://api.sandbox.dnsimple.com/v2",
    retry: false
  )
```

`new_client/2` takes a keyword list requiring `account_id` for both account
tokens (`dnsimple_a_`) and user tokens (`dnsimple_u_`). IDs must be positive
integers or all-digit positive numeric strings, normalized once to an integer.
Missing or malformed constructor configuration raises `ArgumentError` before
HTTP. Other options configure Req, including `base_url`, `headers`, `adapter`,
`retry`, and `receive_timeout`.

The client remains a `Req.Request`, with scope in internal Req metadata, so
`Req.merge/2` and custom adapters keep working. Pass it as the first argument
to every operation. Neither constructor nor `for_account/2` performs HTTP,
discovers accounts, checks permissions, or evaluates dynamic token callbacks.
Callbacks remain lazy per-request authentication. `OAuth.exchange_code/2`
retains transport and base URL but removes inherited authorization without
evaluating a dynamic token callback.

For new global/discovery workflows use `ReqDnsimple.new_unscoped_client/1,2`.
It accepts the same transport options but rejects any `account_id` option.
`ReqDnsimple.new_client/1` retains its exact legacy unscoped behavior,
including accepting account tokens; do not claim that legacy calls now reject
them.

### Account scope and explicit-account compatibility

Every operation that previously took `account_id` as its second argument has a
new form omitting that argument. This includes `list_page`, `list_all`, `list`
aliases, applied Service operations, root shortcuts, `ns_records`, and the
existing zone-listing bang helpers. Optional trailing options work in both
shapes.

```elixir
{:ok, zones} = ReqDnsimple.Zone.list(client, name_like: "example")
{:ok, zone} = ReqDnsimple.Zone.get(client, "example.com")

other_id = System.fetch_env!("DNSIMPLE_OTHER_ACCOUNT_ID")
other_client = ReqDnsimple.for_account(client, other_id)

# An explicit account wins for one call without rebinding either client.
{:ok, other_zones} = ReqDnsimple.Zone.list(client, other_id, per_page: 20)
{:ok, original_zones} = ReqDnsimple.Zone.list(client, per_page: 20)

# Legacy construction and explicit-account calls remain supported.
legacy = ReqDnsimple.new_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:ok, zones} = ReqDnsimple.Zone.list(legacy, account_id)
```

`for_account/2` validates the same positive ID forms and returns an immutable
copy with identical auth, base URL, options, and adapter. The original client
is unchanged; DNSimple remains the authority on permissions.

New account-free calls on unscoped clients return
`{:error, :missing_account_id}` locally, without HTTP or callback evaluation.
Bang forms raise `ReqDnsimple.Error` with `reason: :missing_account_id`.
Invalid operation attributes/options retain the established
`NimbleOptions.ValidationError` behavior and no result shape changes.

Global `whoami/1`, `Account.list/1`, `OAuth.exchange_code/2`, TLD catalogs, and
Service global catalogs need no scope and also work with scoped clients.
Applying or listing services applied to a domain is account-scoped, unlike
listing the global Service catalog.

The root `list_zones`, `list_zones!`, `list_contacts`, and
`list_billing_charges` helpers accept the same options as their resource
modules in both scoped and explicit-account forms.

## Return Value Patterns

Different modules use slightly different return conventions:
Arity lists below include both scoped and legacy explicit-account forms;
omitting the account argument never changes the success or failure shape.

| Module | Success | Failure |
|--------|---------|---------|
| `OAuth.exchange_code/2` | `{:ok, %OAuth.Token{}}` | `{:error, reason}` |
| `Account.list/1` | `[%Account{}, ...]` | `{:error, reason}` |
| `Zone.list/1,2,3` | `{:ok, [%Zone{}, ...]}` | `{:error, reason}` |
| `ReqDnsimple.list_zones!/1,2,3` and `Zone.list!/1,2,3` | `[%Zone{}, ...]` | Raises |
| `Zone.list_page/1,2,3` | `{:ok, {[%Zone{}, ...], pagination}}` | `{:error, reason}` |
| `Zone.list_all/1,2,3` | `{:ok, [%Zone{}, ...]}` | `{:error, reason}` |
| `Zone.get/2,3` | `{:ok, %Zone{}}` | `{:error, reason}` |
| `Zone.activate/2,3` | `{:ok, %Zone{}}` | `{:error, reason}` |
| `Zone.deactivate/2,3` | `{:ok, %Zone{}}` | `{:error, reason}` |
| `ZoneRecord.list/2,3,4` | `{:ok, {[%ZoneRecord{}, ...], pagination}}` | `{:error, reason}` |
| `ZoneRecord.list_page/2,3,4` | `{:ok, {[%ZoneRecord{}, ...], pagination}}` | `{:error, reason}` |
| `ZoneRecord.list_all/2,3,4` | `{:ok, [%ZoneRecord{}, ...]}` | `{:error, reason}` |
| `ZoneRecord.create/3,4` | `{:ok, %ZoneRecord{}}` | `{:error, reason}` |
| `ZoneRecord.update/4,5` | `{:ok, %ZoneRecord{}}` | `{:error, reason}` |
| `ZoneRecord.delete/3,4` | `:ok` | `{:error, reason}` |
| `ZoneRecord.get/3,4` | `{:ok, %ZoneRecord{}}` | `{:error, :not_found}` |
| `ZoneRecord.check_distribution/3,4` | `{:ok, boolean()}` | `{:error, reason}` |
| `ZoneRecord.batch_change/3,4` | `{:ok, %ZoneRecord.BatchResult{}}` | `{:error, reason}` |
| `Contact.create/2,3` | `{:ok, %Contact{}}` | `{:error, reason}` |
| `Contact.update/3,4` | `{:ok, %Contact{}}` | `{:error, reason}` |
| `Contact.list/1,2,3` | `{:ok, [%Contact{}, ...]}` | `{:error, reason}` |
| `Contact.list_page/1,2,3` | `{:ok, {[%Contact{}, ...], pagination}}` | `{:error, reason}` |
| `Contact.list_all/1,2,3` | `{:ok, [%Contact{}, ...]}` | `{:error, reason}` |
| `Contact.get/2,3` | `{:ok, %Contact{}}` | `{:error, :not_found}` |
| `Contact.delete/2,3` | `:ok` | `{:error, reason}` |
| `Domain.create/2,3` | `{:ok, %Domain{}}` | `{:error, reason}` |
| `Domain.get/2,3` | `{:ok, %Domain{}}` | `{:error, reason}` |
| `Domain.list_page/1,2,3` | `{:ok, {[%Domain{}, ...], pagination}}` | `{:error, reason}` |
| `Domain.list_all/1,2,3` | `{:ok, [%Domain{}, ...]}` | `{:error, reason}` |
| `DnsAnalytics.list_page/1,2,3` and `DnsAnalytics.query/1,2,3` | `{:ok, {%DnsAnalytics.Result{}, pagination}}` | `{:error, reason}` |
| `DnsAnalytics.list_all/1,2,3` | `{:ok, %DnsAnalytics.Result{}}` | `{:error, reason}` |
| `DomainResearch.get_status/2,3` | `{:ok, %DomainResearch{}}` | `{:error, reason}` |
| `Dnssec.get/2,3` | `{:ok, %Dnssec{}}` | `{:error, reason}` |
| `Dnssec.enable/2,3` | `{:ok, %Dnssec{}}` | `{:error, reason}` |
| `Dnssec.disable/2,3` | `:ok` | `{:error, reason}` |
| `Service.get/2` | `{:ok, %Service{}}` | `{:error, reason}` |
| `Service.list_page/1,2` | `{:ok, {[%Service{}, ...], pagination}}` | `{:error, reason}` |
| `Service.list_all/1,2` | `{:ok, [%Service{}, ...]}` | `{:error, reason}` |
| `Service.list_page_applied/2,3,4` and `Service.list_applied/2,3,4` | `{:ok, {[%Service{}, ...], pagination}}` | `{:error, reason}` |
| `Service.list_all_applied/2,3,4` | `{:ok, [%Service{}, ...]}` | `{:error, reason}` |
| `Service.apply/3,4,5` and `Service.unapply/3,4` | `:ok` | `{:error, reason}` |
| `Template.create/2,3` | `{:ok, %Template{}}` | `{:error, reason}` |
| `Template.list_page/1,2,3` | `{:ok, {[%Template{}], pagination}}` | `{:error, reason}` |
| `Template.list_all/1,2,3` | `{:ok, [%Template{}]}` | `{:error, reason}` |
| `Template.update/3,4` | `{:ok, %Template{}}` | `{:error, reason}` |
| `Template.apply/3,4` | `:ok` | `{:error, reason}` |
| `Template.delete/2,3` | `:ok` | `{:error, reason}` |
| `TemplateRecord.create/3,4` | `{:ok, %TemplateRecord{}}` | `{:error, reason}` |
| `TemplateRecord.get/3,4` | `{:ok, %TemplateRecord{}}` | `{:error, reason}` |
| `TemplateRecord.list_page/2,3,4` | `{:ok, {[%TemplateRecord{}], pagination}}` | `{:error, reason}` |
| `TemplateRecord.list_all/2,3,4` | `{:ok, [%TemplateRecord{}]}` | `{:error, reason}` |
| `TemplateRecord.delete/3,4` | `:ok` | `{:error, reason}` |
| `DelegationSignerRecord.create/3,4` | `{:ok, %DelegationSignerRecord{}}` | `{:error, reason}` |
| `DelegationSignerRecord.get/3,4` | `{:ok, %DelegationSignerRecord{}}` | `{:error, reason}` |
| `DelegationSignerRecord.list_page/2,3,4` | `{:ok, {[%DelegationSignerRecord{}], pagination}}` | `{:error, reason}` |
| `DelegationSignerRecord.list_all/2,3,4` | `{:ok, [%DelegationSignerRecord{}]}` | `{:error, reason}` |
| `DelegationSignerRecord.delete/3,4` | `:ok` | `{:error, reason}` |
| `EmailForward.create/3,4` | `{:ok, %EmailForward{}}` | `{:error, reason}` |
| `EmailForward.get/3,4` | `{:ok, %EmailForward{}}` | `{:error, reason}` |
| `EmailForward.list/2,3,4` and `EmailForward.list_page/2,3,4` | `{:ok, {[%EmailForward{}], pagination}}` | `{:error, reason}` |
| `EmailForward.list_all/2,3,4` | `{:ok, [%EmailForward{}]}` | `{:error, reason}` |
| `EmailForward.delete/3,4` | `:ok` | `{:error, reason}` |
| `Webhook.list/1,2,3` | `{:ok, [%Webhook{}]}` | `{:error, reason}` |
| `Webhook.create/2,3` | `{:ok, %Webhook{}}` | `{:error, reason}` |
| `Webhook.get/2,3` | `{:ok, %Webhook{}}` | `{:error, reason}` |
| `Webhook.delete/2,3` | `:ok` | `{:error, reason}` |
| `DomainPush.initiate/3,4` | `{:ok, %DomainPush{}}` | `{:error, reason}` |
| `DomainPush.list_page/1,2,3` | `{:ok, {[%DomainPush{}], pagination}}` | `{:error, reason}` |
| `DomainPush.list_all/1,2,3` | `{:ok, [%DomainPush{}]}` | `{:error, reason}` |
| `DomainPush.accept/3,4` | `:ok` | `{:error, reason}` |
| `DomainPush.reject/2,3` | `:ok` | `{:error, reason}` |
| `Certificate.purchase_letsencrypt/2,3,4` | `{:ok, %Certificate.Purchase{}}` | `{:error, reason}` |
| `Certificate.purchase_letsencrypt_renewal/3,4,5` | `{:ok, %Certificate.Renewal{}}` | `{:error, reason}` |
| `Certificate.issue_letsencrypt/3,4` | `{:ok, %Certificate{}}` | `{:error, reason}` |
| `Certificate.issue_letsencrypt_renewal/4,5` | `{:ok, %Certificate{}}` | `{:error, reason}` |
| `Certificate.list_page/2,3,4` | `{:ok, {[%Certificate{}], pagination}}` | `{:error, reason}` |
| `Certificate.list/2,3,4` | `{:ok, {[%Certificate{}], pagination}}` | `{:error, reason}` |
| `Certificate.list_all/2,3,4` | `{:ok, [%Certificate{}]}` | `{:error, reason}` |
| `Certificate.get/3,4` | `{:ok, %Certificate{}}` | `{:error, reason}` |
| `Certificate.download/3,4` | `{:ok, %Certificate.Download{}}` | `{:error, reason}` |
| `Certificate.get_private_key/3,4` | `{:ok, %Certificate.PrivateKey{}}` | `{:error, reason}` |
| `Registrar.check/2,3` | `{:ok, %Registrar.CheckResult{}}` | `{:error, reason}` |
| `Registrar.get_prices/2,3` | `{:ok, %Registrar.Prices{}}` | `{:error, reason}` |
| `Registrar.get_transfer_lock/2,3` | `{:ok, %Registrar.TransferLock{}}` | `{:error, reason}` |
| `Registrar.enable_transfer_lock/2,3` | `{:ok, %Registrar.TransferLock{}}` | `{:error, reason}` |
| `Registrar.disable_transfer_lock/2,3` | `{:ok, %Registrar.TransferLock{}}` | `{:error, reason}` |
| `RegistrantChange.create/2,3` | `{:ok, %RegistrantChange{}}` | `{:error, reason}` |
| `RegistrantChange.get/2,3` | `{:ok, %RegistrantChange{}}` | `{:error, reason}` |
| `RegistrantChange.list_page/1,2,3` and `RegistrantChange.list/1,2,3` | `{:ok, {[RegistrantChange.t()], pagination}}` | `{:error, reason}` |
| `RegistrantChange.list_all/1,2,3` | `{:ok, [RegistrantChange.t()]}` | `{:error, reason}` |
| `RegistrantChange.cancel/2,3` | `{:ok, %RegistrantChange{}}` or `:ok` | `{:error, reason}` |
| `Registrar.enable_whois_privacy/2,3` | `{:ok, %Registrar.WhoisPrivacy{}}` | `{:error, reason}` |
| `Registrar.disable_whois_privacy/2,3` | `{:ok, %Registrar.WhoisPrivacy{}}` | `{:error, reason}` |
| `Registrar.register/3,4` | `{:ok, %Registrar.Registration{}}` | `{:error, reason}` |
| `Registrar.transfer/3,4` | `{:ok, %Registrar.Transfer{}}` | `{:error, reason}` |
| `Registrar.renew/2,3,4` | `{:ok, %Registrar.Renewal{}}` | `{:error, reason}` |
| `Registrar.restore/2,3,4` | `{:ok, %Registrar.Restore{}}` | `{:error, reason}` |
| `Registrar.get_delegation/2,3` | `{:ok, [String.t()]}` | `{:error, reason}` |
| `BillingCharge.list/1,2,3` | `{:ok, [%BillingCharge{}, ...]}` | `{:error, reason}` |
| `BillingCharge.list_page/1,2,3` | `{:ok, {[%BillingCharge{}, ...], pagination}}` | `{:error, reason}` |
| `BillingCharge.list_all/1,2,3` | `{:ok, [%BillingCharge{}, ...]}` | `{:error, reason}` |
| `Zone.get_zone_file/2,3` | `{:ok, binary()}` | `{:error, reason}` |
| `Zone.check_zone_distribution/2,3` | `{:ok, boolean()}` | `{:error, reason}` |
| `Zone.update_ns_records/3,4` | `{:ok, [%ZoneRecord{}, ...]}` | `{:error, reason}` |

`whoami/1` returns `{:user, user}` or `{:account, account}` according to the
single non-null identity in the successful response, regardless of token prefix
or custom Req authentication. If both identities are present or absent, it
preserves the complete response body in `{:unknown_token, body}`.

Note that `Account.list/1` returns a bare list, not an `{:ok, list}` tuple.
For scoped `Zone`, `Contact`, and `BillingCharge`, `list_page/1,2` returns
`{:ok, {items, pagination}}` and `list_all/1,2` returns every item as
`{:ok, items}`. Scoped `ZoneRecord` provides the corresponding `list_page/2,3`
and `list_all/2,3` interfaces with the zone argument retained. Prefer these
explicit pagination interfaces instead of assuming all `list` aliases return
the same shape. Every `list_all` starts at page one, preserves other
filters and pagination size, and rejects an explicit `page` option.
Ordinary HTTP failures return
`{:error, %{status: status, response: response_body}}`. Existing
endpoint-specific mappings such as `:not_found`, `:unauthorized`, and `:timeout`
take precedence. If a response includes `Retry-After`, the generic error map
also includes `retry_after: value`.

### Bang Functions

`ReqDnsimple.list_zones!/1,2,3` and `Zone.list!/1,2,3` return the zone list directly,
without changing the existing one-page request behavior. No other endpoint
has a named bang counterpart yet.

`ReqDnsimple.unwrap!/1` supports `{:ok, value}`, `:ok`, and `{:error, reason}`.
It returns successful values unchanged, preserving pagination tuples, and
returns `:ok` for bodyless success. Existing exception structs are raised
unchanged; other errors raise `ReqDnsimple.Error` with the original error
available in `exception.reason`. Unsupported shapes raise `ArgumentError`,
so do not pass the bare lists from `Account.list/1` or `ns_records/2,3`, or the
tagged identity results from `whoami/1`.

## Common Patterns

### Listing with Filters, Sorting, and Pagination

Most list operations accept keyword options validated by NimbleOptions:

```elixir
# Filtering
ReqDnsimple.Zone.list(client, name_like: "example")
ReqDnsimple.ZoneRecord.list(client, zone, name: "www", type: "A")

# Sorting (bare fields default to :asc; tuples accept :asc/:desc)
ReqDnsimple.Zone.list(client, sort: [name: :desc])
ReqDnsimple.ZoneRecord.list(client, zone, sort: [:type, name: :desc])

# Pagination
ReqDnsimple.Zone.list(client, page: 2, per_page: 50)
```

Malformed option and attribute containers return
`{:error, %NimbleOptions.ValidationError{}}` without dispatching an HTTP request.

Sort options are lists like `[:id, name: :desc]`. Supported fields are endpoint-specific:
zones accept `:id` and `:name`; records accept `:id`, `:name`, `:content`, and `:type`;
contacts accept `:id`, `:label`, and `:email`; billing charges accept only `:invoiced`.
They are automatically converted to DNSimple's `"name:asc,id:desc"` string format
by `ReqDnsimple.convert_sort_to_string/1`.

DNS analytics use the same ordered sort form for `:date`, `:zone_name`, and
`:volume`. Their `:groupings` option is an ordered list containing only `:date`
and `:zone_name`; an explicit empty list is sent as an empty query value.
`start_date` and `end_date` are ISO 8601 dates with an inclusive span of at most
31 days. Scoped `list_page/2` and `query/2` return a typed tabular result plus
pagination, while `list_all/2` combines only pages whose headers and echoed
query settings remain compatible.

### CRUD Operations on Zone Records

These are API reference snippets. For a runnable example that requires explicit
mutation consent and a disposable test zone, use the
[sandbox record lifecycle](samples/README.md#opt-in-mutation-one-record-lifecycle).

```elixir
# Create — attrs is a keyword list, name/type/content are required
{:ok, record} = ReqDnsimple.ZoneRecord.create(client, "example.com",
  name: "www", type: "A", content: "93.184.215.14", ttl: 3600
)

# Read
{:ok, record} = ReqDnsimple.ZoneRecord.get(client, "example.com", record_id)

# Update — only pass the fields you want to change
{:ok, record} = ReqDnsimple.ZoneRecord.update(client, "example.com", record_id,
  content: "93.184.215.15"
)

# Delete
:ok = ReqDnsimple.ZoneRecord.delete(client, "example.com", record_id)

# Check distribution
{:ok, distributed?} =
  ReqDnsimple.ZoneRecord.check_distribution(client, "example.com", record_id)

# Atomic batch; each operation list is optional
{:ok, %ReqDnsimple.ZoneRecord.BatchResult{} = result} =
  ReqDnsimple.ZoneRecord.batch_change(client, "example.com",
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

### Explicit Account Discovery

For an account token, use the account identity returned by an explicit request:

```elixir
discovery = ReqDnsimple.new_unscoped_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:account, %{"id" => id}} = ReqDnsimple.whoami(discovery)
client = ReqDnsimple.for_account(discovery, id)

{:ok, zones} = ReqDnsimple.Zone.list(client)
```

For a user token, list accessible accounts and make an explicit user/application
selection:

```elixir
discovery = ReqDnsimple.new_unscoped_client(System.fetch_env!("DNSIMPLE_TOKEN"))
accounts = ReqDnsimple.Account.list(discovery)
# Bare list on success. Display account IDs, then select one deliberately.
Enum.map(accounts, & &1.id)

client = ReqDnsimple.for_account(discovery, System.fetch_env!("DNSIMPLE_ACCOUNT_ID"))
{:ok, {records, _pagination}} = ReqDnsimple.ZoneRecord.list_page(client, "example.com")
```

Never choose `hd(accounts)` or the first account automatically. Never infer an
account ID from `whoami`'s `user.id`. Prefix classification is guidance only;
the response and DNSimple's permission checks determine identity and access.
The existing `token_type/1` helper evaluates a dynamic callback when passed a
client, so do not call it during construction, re-scoping, or sample setup.
Use separate immutable `for_account/2` copies for multiple accounts; changing
scope does not change credentials or prove that a token can access the account.
The [discovery samples](samples/README.md#read-only-programs) handle errors and
validate explicit account selection rather than silently falling back.

### Reading Apex Name Server Records

`ReqDnsimple.ns_records/2,3` reads all apex NS records by listing zone records
with exact `name=""` and `type="NS"` filters. It is read-only and returns a bare
list of `ReqDnsimple.NsRecord` structs. Apex zone records are separate from the
domain's registrar delegation. `Zone.update_ns_records/3,4` explicitly replaces
the hosted zone's apex NS records from `ns_names`, `ns_set_ids`, or both. It
preserves explicit empty lists and performs no lookup or merge, so callers
retaining vanity configuration must include those names or sets themselves.
The update does not change registrar delegation.

### Enabling and Disabling Vanity Name Servers

`ReqDnsimple.VanityNameServer.enable/2,3` sends one bodyless request and returns
the typed vanity A and AAAA records created by DNSimple. It accepts a domain
name or integer ID. DNSimple can return plan or payment errors when the feature
is unavailable.

`ReqDnsimple.VanityNameServer.disable/2,3` sends one bodyless request to remove a
domain's vanity A and AAAA configuration. It accepts a domain name or integer
ID. Neither operation inspects or changes registrar delegation, and disabling
does not delete records individually.

### Listing, Registering, Retrieving, and Deregistering Webhook Endpoints

`ReqDnsimple.Webhook.list/1,2,3` sends one bodyless request and returns the
non-paginated collection as typed webhooks. It supports ordered sorting by `id`.
Scoped `create/2` requires an absolute HTTPS callback URL and sends it unchanged
in one POST request. Scoped `get/2` sends one bodyless request and returns the
registered callback URL with its nullable suppression timestamp. Scoped
`delete/2` returns `:ok`
only for HTTP 204. Retrieval and deletion accept an integer or numeric-string
webhook ID. None of these operations contacts the callback URL or inspects
deliveries.

## Module Reference

- `ReqDnsimple` — Preferred scoped creation (`new_client/2`), explicit unscoped
  creation (`new_unscoped_client/1,2`), immutable re-scoping (`for_account/2`),
  legacy unscoped creation (`new_client/1`), response-based identity
  discovery (`whoami/1`), token-prefix inspection (`token_type/1`),
  `ns_records/2,3`, convenience delegates, and `from_json/3` for JSON→struct conversion.
- `ReqDnsimple.OAuth` — Unauthenticated authorization-code exchange for
  confidential clients or public clients using a 43-128 character RFC 7636
  verifier. It returns an unenveloped typed token with nullable `scope` and
  never invokes inherited bearer authentication.
- `ReqDnsimple.Account` — Account listing. Struct: `id`, `email`, optional `name`,
  `plan_identifier`, `created_at`, `updated_at`. DNSimple's examples and official
  SDK include `name` even though its OpenAPI schema omits it.
- `ReqDnsimple.Zone` — Zone listing and retrieval, DNS-service
  activation/deactivation, apex NS updates, zone file retrieval, and
  distribution checks. Deactivation stops resolution without deleting the
  zone, domain, or records.
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
- `ReqDnsimple.Contact` — Contact creation, partial updates, listing, retrieval, and
  deletion. 14 contact fields + timestamps.
- `ReqDnsimple.Template` — Creating, listing, retrieving, updating, applying, or
  deleting an account template. Listing supports explicit pages or deliberate
  complete enumeration, with ordered `id`/`name`/`sid` sorting. Creation requires
  a short identifier and name, accepts an optional description, and returns a
  typed template without creating records or applying it to a domain. Updates
  patch only supplied metadata, using the current short name or integer ID in the
  path even when changing `sid`. Typed responses include parsed timestamps.
- `ReqDnsimple.TemplateRecord` — Creating, retrieving, listing, or deleting records
  from an account template by template short name or ID. Listing supports explicit
  pages or deliberate complete enumeration, with ordered `id`/`name`/`content`/`type`
  sorting. Creation requires name, type, and content, accepts optional TTL and
  priority, and sends a flat JSON object. Typed responses preserve literal
  placeholders, zero TTL/priority values, and nullable priority while returning
  parsed timestamps. Deletion does not remove the template or records previously
  applied to domains.
- `ReqDnsimple.Domain` — Hosted-domain creation, retrieval, paginated listing,
  deliberate complete enumeration, and explicit deletion by name or ID. Listing
  supports `name_like` and `registrant_id` filters plus ordered
  `id`/`name`/`expiration` sorting. Creation sends one request and may incur the
  DNS-service subscription charge; it does not register or purchase the domain,
  change delegation, verify ownership, or create a zone separately. Retrieval
  returns registration state, privacy, renewal, and nullable expiry metadata.
  Deletion is irreversible within the account, but does not delete a registration
  at the registry or produce a refund.
- `ReqDnsimple.DomainResearch` — Paid domain-availability research through the
  dedicated endpoint. Requires the `domain_research_read` OAuth scope and
  returns request ID, domain, availability, and research errors without falling
  back to a registrar availability check.
- `ReqDnsimple.Dnssec` — Typed DNSSEC status retrieval, enablement, and explicit
  disablement by domain name or ID. Retrieval and enablement keep enabled and
  active as separate states and parse creation/update timestamps. DNSimple
  handles registry delegation-signer submission for domains registered with
  DNSimple; hosted-only domains require caller-managed registrar coordination.
  For hosted-only domains, registry delegation-signer records must be removed
  before disablement; disablement does not remove them or prompt for
  confirmation.
- `ReqDnsimple.DelegationSignerRecord` — Typed creation, retrieval, paginated
  listing, and explicit deletion of registry delegation-signer records by domain
  name or ID. Scoped `list_page/3` and `list/3` return one page; `list_all/3` explicitly
  enumerates from page one while retaining `id`/`created_at` sorting and page
  size. Creation accepts a string algorithm with either a complete DS tuple or
  KEY public key. DS and KEY proof fields that do not apply are `nil`. Deletion
  does not disable DNSSEC or delete hosted-zone records.
- `ReqDnsimple.EmailForward` — Typed creation, retrieval, paginated listing,
  deliberate complete enumeration, and explicit deletion of domain email
  forwards. Scoped `list_page/3` and `list/3` return one page; `list_all/3` starts at
  page one while retaining `id`/`alias_email`/`destination_email` sorting and
  page size. Creation sends the local-part alias unchanged and neither provisions
  DNS records nor sends test email. Responses preserve the full alias email,
  destination, activation state, and timestamps. Deletion does not modify MX
  records.
- `ReqDnsimple.DomainPush` — Initiate a push from a source account using exactly
  one target-account identifier or deprecated email, list typed pending incoming
  pushes for a target account one page at a time or by deliberate complete
  enumeration, accept one with an explicit target-account contact, or reject it
  without deleting the source domain.
- `ReqDnsimple.VanityNameServer` — Enable or disable a domain's vanity A and
  AAAA configuration by name or ID without changing registrar delegation.
- `ReqDnsimple.Webhook` — List typed webhook registrations with optional `id`
  sorting, register an absolute HTTPS callback URL, retrieve one registration,
  or explicitly deregister it by integer or numeric-string ID without
  contacting its callback URL. Struct: `id`, `url`, nullable `suppressed_at`.
- `ReqDnsimple.Certificate` — Order typed Let's Encrypt purchases and renewals
  without automatic issuance or deployment; renewal orders preserve distinct
  old and new certificate IDs. Explicitly request initial or renewal issuance
  by the required certificate and order IDs without polling or deployment. List
  one sorted page with pagination or deliberately enumerate every page in server
  order. Retrieve typed certificate metadata, including pending nullable
  CSR/expiry values; download its server, nullable root, and ordered intermediate
  chain; or retrieve its private key as byte-preserved PEM strings without
  parsing, logging, persisting, or writing files.
- `ReqDnsimple.RegistrantChange` — Start a registrar contact-change request from
  explicit domain/contact identifiers; list one filtered, sorted page or
  explicitly enumerate all matching pages; retrieve one by integer ID; or
  cancel it without polling. Creation returns immediate and pending responses
  without a requirements check. Cancellation returns the typed current request
  when asynchronous or `:ok` when immediate. Registry extended attributes
  retain string keys and values, and the registry lock-lift date may be `nil`.
- `ReqDnsimple.Tld` — List one sorted page of typed TLD capabilities or
  deliberately enumerate all pages in server order, retrieve one TLD's
  capabilities, or retrieve its non-paginated, typed registry
  extended-attribute definitions. Numeric-string name-server bounds are
  normalized to integers and omitted bounds remain `nil`. Arbitrary attribute
  names and option values remain strings, free-text attributes retain empty
  option lists, omitted display titles remain `nil`, and present titles are
  strings.
- `ReqDnsimple.Registrar` — Check domain availability by name, explicitly
  retrieve registration and lifecycle prices by name, retrieve, enable, or
  disable the transfer lock by name or ID, authorize transfer-out by name,
  enable or disable automatic renewal by name or ID, enable or disable WHOIS
  privacy by name or ID, submit a registration or inbound transfer for an
  existing contact, submit a renewal or expired-domain restore by name, or
  retrieve or replace registrar delegation by name or ID.
  The low-volume check preserves availability, premium, and optional trustee
  flags without using paid Domain Research, registering the domain, or retrying
  rate limits. Price retrieval preserves numeric registration, renewal,
  transfer, restore, and trustee values; optional transfer and trustee prices
  are `nil` when omitted, and no purchase is initiated. Transfer-lock retrieval
  preserves both boolean states without reading the domain or changing the
  lock. Changing auto-renewal is a single bodyless request and preserves
  registry or TLD refusal errors without reading current state or immediately
  renewing. Renewal accepts an optional period and exact premium-price string
  and returns a typed immediate or asynchronous renewal job without preflight
  requests or polling. Registration requires a contact ID, preserves omitted
  options, false booleans, string-keyed extended attributes, and exact premium
  prices, and returns a typed immediate or asynchronous job. Registration and
  service charges remain server-determined, and the operation does not perform
  availability, price, contact, domain-creation, or polling requests. Inbound
  transfer requires a contact ID, leaves authorization TLD-conditional, and
  preserves omitted options, false booleans, string-keyed extended attributes,
  and exact premium prices. It sends no TLD, price, unlock, transfer-out
  authorization, or polling requests. Restore accepts only an optional exact
  premium-price string and returns a typed immediate or asynchronous restore
  job; DNSimple determines charges and eligibility, and refusals remain
  explicit errors without an automatic renewal, purchase, or poll. Delegation
  retrieval returns the ordered hostnames exactly as supplied. Delegation
  replacement preserves the supplied order and explicit empty lists, sends one
  request, and does not read or merge the prior delegation. Both are distinct
  from hosted-zone apex NS records and `Zone.update_ns_records/3,4`.
- `ReqDnsimple.PrimaryServer` — Secondary-DNS primary server creation,
  retrieval, paginated listing, zone linking/unlinking, and explicit deletion. Listing
  supports ordered `id`/`name` sorting: scoped `list_page/2` and `list/2` return one
  page with string-keyed metadata, while `list_all/2` explicitly enumerates
  from page one. Creation requires a name and IP, preserves a supplied integer
  port (including zero), omits an absent port, and performs no reachability or
  follow-up requests. Linking and unlinking require a zone name and send one
  request without looking up or creating either resource. Unlinking retains the
  primary server and zone. Struct: `id`, `account_id`, `name`, `ip`, integer
  `port`, ordered `linked_secondary_zones`, and timestamps. Deletion does not
  unlink zones or perform DNS requests.
- `ReqDnsimple.SecondaryZone` — Create a secondary DNS zone from its required
  name and return the existing `ReqDnsimple.Zone` struct. An omitted `active`
  field remains `nil`, as does a null `last_transferred_at`. Ownership or
  subscription errors are returned without delegation changes, primary-server
  creation, verification requests, or other follow-up work.
- `ReqDnsimple.Service` — Retrieve a global one-click service by sid or ID,
  including typed timestamps and setting definitions; list one paginated page
  or explicitly enumerate the global catalog; list one paginated page or
  explicitly enumerate all services applied to a domain; or apply/unapply one.
  Catalog listing supports ordered `id`/`sid` sorting, `page`, and `per_page`.
  Applied-service listing accepts only `page` and `per_page`; both full
  enumeration helpers reject an explicit page. Optional dynamic settings use
  string keys. Omitted settings send no body, while an explicit empty map is
  preserved. Applying performs no catalog lookup or per-record requests;
  unapplying sends one bodyless request and does not delete records individually.
- `ReqDnsimple.NsRecord` — Name server record struct and JSON parsing.
- `ReqDnsimple.Helper` — Req helper for incrementally appending URL path segments
  and merging params/path_params onto a `Req.Request`.

## Important Notes

- All API functions take a `Req.Request` client as the first argument
- Bind an explicit account ID with `new_client/2` or `for_account/2` for most
  operations; legacy explicit-account calls remain supported
- Discover account tokens through explicit `whoami/1`; discover user-token
  accounts through `Account.list/1` and explicit user/application selection
- Zone operations accept zone names (e.g., `"example.com"`) as identifiers;
  `Zone.update_ns_records/3,4` also accepts a numeric zone ID
- Options are validated at call time via NimbleOptions — invalid options return
  `{:error, %NimbleOptions.ValidationError{}}`
- The `create` and `update` functions for ZoneRecord take keyword lists, not maps
- `from_json/3` is a shared utility for converting DNSimple JSON responses to Elixir structs
- Valid ISO 8601 response timestamps, including nonzero offsets, are normalized
  to UTC `DateTime` values; missing and null timestamps remain `nil`

## Runnable Samples

The [sample index](samples/README.md) lists every `mix run samples/*.exs` program,
its required environment variables, and the read-only Livebook notebook.
Examples cover scoped reads and bang helpers, filtered pagination versus
complete enumeration, both discovery workflows, multiple accounts, dynamic
credentials, and a custom base URL or trusted reverse proxy. Only the record
lifecycle mutates anything: it requires `DNSIMPLE_ALLOW_MUTATIONS=true` and a
user-supplied `DNSIMPLE_TEST_ZONE`, recommends DNSimple sandbox, and deletes
only its newly created record. Never log clients, tokens, or private keys.
