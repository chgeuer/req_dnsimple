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
as the first argument to every API call. `OAuth.exchange_code/2` is the
exception: it retains the client's transport and base URL but removes inherited
authorization without evaluating a dynamic token callback.

## Return Value Patterns

Different modules use slightly different return conventions:

| Module | Success | Failure |
|--------|---------|---------|
| `OAuth.exchange_code/2` | `{:ok, %OAuth.Token{}}` | `{:error, reason}` |
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
| `Domain.create/3` | `{:ok, %Domain{}}` | `{:error, reason}` |
| `Domain.get/3` | `{:ok, %Domain{}}` | `{:error, reason}` |
| `Domain.list_page/3` | `{:ok, {[%Domain{}, ...], pagination}}` | `{:error, reason}` |
| `Domain.list_all/3` | `{:ok, [%Domain{}, ...]}` | `{:error, reason}` |
| `DomainResearch.get_status/3` | `{:ok, %DomainResearch{}}` | `{:error, reason}` |
| `Dnssec.get/3` | `{:ok, %Dnssec{}}` | `{:error, reason}` |
| `Dnssec.enable/3` | `{:ok, %Dnssec{}}` | `{:error, reason}` |
| `Dnssec.disable/3` | `:ok` | `{:error, reason}` |
| `Service.get/2` | `{:ok, %Service{}}` | `{:error, reason}` |
| `Service.apply/4,5` | `:ok` | `{:error, reason}` |
| `Template.apply/4` | `:ok` | `{:error, reason}` |
| `Template.delete/3` | `:ok` | `{:error, reason}` |
| `TemplateRecord.get/4` | `{:ok, %TemplateRecord{}}` | `{:error, reason}` |
| `TemplateRecord.delete/4` | `:ok` | `{:error, reason}` |
| `DelegationSignerRecord.create/4` | `{:ok, %DelegationSignerRecord{}}` | `{:error, reason}` |
| `DelegationSignerRecord.get/4` | `{:ok, %DelegationSignerRecord{}}` | `{:error, reason}` |
| `DelegationSignerRecord.list_page/4` | `{:ok, {[%DelegationSignerRecord{}], pagination}}` | `{:error, reason}` |
| `DelegationSignerRecord.list_all/4` | `{:ok, [%DelegationSignerRecord{}]}` | `{:error, reason}` |
| `DelegationSignerRecord.delete/4` | `:ok` | `{:error, reason}` |
| `EmailForward.create/4` | `{:ok, %EmailForward{}}` | `{:error, reason}` |
| `EmailForward.get/4` | `{:ok, %EmailForward{}}` | `{:error, reason}` |
| `EmailForward.delete/4` | `:ok` | `{:error, reason}` |
| `Webhook.get/3` | `{:ok, %Webhook{}}` | `{:error, reason}` |
| `Webhook.delete/3` | `:ok` | `{:error, reason}` |
| `DomainPush.initiate/4` | `{:ok, %DomainPush{}}` | `{:error, reason}` |
| `DomainPush.list_page/3` | `{:ok, {[%DomainPush{}], pagination}}` | `{:error, reason}` |
| `DomainPush.list_all/3` | `{:ok, [%DomainPush{}]}` | `{:error, reason}` |
| `DomainPush.accept/4` | `:ok` | `{:error, reason}` |
| `DomainPush.reject/3` | `:ok` | `{:error, reason}` |
| `Certificate.purchase_letsencrypt/3,4` | `{:ok, %Certificate.Purchase{}}` | `{:error, reason}` |
| `Certificate.purchase_letsencrypt_renewal/4,5` | `{:ok, %Certificate.Renewal{}}` | `{:error, reason}` |
| `Certificate.get/4` | `{:ok, %Certificate{}}` | `{:error, reason}` |
| `Certificate.download/4` | `{:ok, %Certificate.Download{}}` | `{:error, reason}` |
| `Certificate.get_private_key/4` | `{:ok, %Certificate.PrivateKey{}}` | `{:error, reason}` |
| `Registrar.check/3` | `{:ok, %Registrar.CheckResult{}}` | `{:error, reason}` |
| `Registrar.get_prices/3` | `{:ok, %Registrar.Prices{}}` | `{:error, reason}` |
| `Registrar.get_transfer_lock/3` | `{:ok, %Registrar.TransferLock{}}` | `{:error, reason}` |
| `Registrar.enable_transfer_lock/3` | `{:ok, %Registrar.TransferLock{}}` | `{:error, reason}` |
| `Registrar.disable_transfer_lock/3` | `{:ok, %Registrar.TransferLock{}}` | `{:error, reason}` |
| `RegistrantChange.create/3` | `{:ok, %RegistrantChange{}}` | `{:error, reason}` |
| `RegistrantChange.get/3` | `{:ok, %RegistrantChange{}}` | `{:error, reason}` |
| `RegistrantChange.list_page/2,3` and `RegistrantChange.list/2,3` | `{:ok, {[RegistrantChange.t()], pagination}}` | `{:error, reason}` |
| `RegistrantChange.list_all/2,3` | `{:ok, [RegistrantChange.t()]}` | `{:error, reason}` |
| `RegistrantChange.cancel/3` | `{:ok, %RegistrantChange{}}` or `:ok` | `{:error, reason}` |
| `Registrar.enable_whois_privacy/3` | `{:ok, %Registrar.WhoisPrivacy{}}` | `{:error, reason}` |
| `Registrar.disable_whois_privacy/3` | `{:ok, %Registrar.WhoisPrivacy{}}` | `{:error, reason}` |
| `Registrar.register/4` | `{:ok, %Registrar.Registration{}}` | `{:error, reason}` |
| `Registrar.transfer/4` | `{:ok, %Registrar.Transfer{}}` | `{:error, reason}` |
| `Registrar.renew/3,4` | `{:ok, %Registrar.Renewal{}}` | `{:error, reason}` |
| `Registrar.restore/3,4` | `{:ok, %Registrar.Restore{}}` | `{:error, reason}` |
| `Registrar.get_delegation/3` | `{:ok, [String.t()]}` | `{:error, reason}` |
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

Malformed option and attribute containers return
`{:error, %NimbleOptions.ValidationError{}}` without dispatching an HTTP request.

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

### Enabling and Disabling Vanity Name Servers

`ReqDnsimple.VanityNameServer.enable/3` sends one bodyless request and returns
the typed vanity A and AAAA records created by DNSimple. It accepts a domain
name or integer ID. DNSimple can return plan or payment errors when the feature
is unavailable.

`ReqDnsimple.VanityNameServer.disable/3` sends one bodyless request to remove a
domain's vanity A and AAAA configuration. It accepts a domain name or integer
ID. Neither operation inspects or changes registrar delegation, and disabling
does not delete records individually.

### Retrieving and Deregistering Webhook Endpoints

`ReqDnsimple.Webhook.get/3` sends one bodyless request and returns the registered
callback URL with its nullable suppression timestamp. `delete/3` returns `:ok`
only for HTTP 204. Both accept an integer or numeric-string webhook ID and do
not contact the callback URL, inspect deliveries, or list registrations first.

## Module Reference

- `ReqDnsimple` — Client creation (`new_client/1`), response-based identity
  discovery (`whoami/1`), token-prefix inspection (`token_type/1`),
  `ns_records/3`, convenience delegates, and `from_json/3` for JSON→struct conversion.
- `ReqDnsimple.OAuth` — Unauthenticated authorization-code exchange for
  confidential clients or public clients using a 43-128 character RFC 7636
  verifier. It returns an unenveloped typed token with nullable `scope` and
  never invokes inherited bearer authentication.
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
- `ReqDnsimple.Template` — Retrieving, applying, or deleting an account template,
  each with one bodyless request. Retrieval returns a typed template with parsed
  timestamps. Domain and template identifiers accept short names or integer IDs.
- `ReqDnsimple.TemplateRecord` — Retrieving or deleting one record from an account
  template by template short name or ID and record ID. Retrieval preserves
  literal placeholders, zero TTL/priority values, and nullable priority while
  returning parsed timestamps. Deletion does not remove the template or records
  previously applied to domains.
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
  name or ID. `list_page/4` and `list/4` return one page; `list_all/4` explicitly
  enumerates from page one while retaining `id`/`created_at` sorting and page
  size. Creation accepts a string algorithm with either a complete DS tuple or
  KEY public key. DS and KEY proof fields that do not apply are `nil`. Deletion
  does not disable DNSSEC or delete hosted-zone records.
- `ReqDnsimple.EmailForward` — Typed creation, retrieval, paginated listing,
  deliberate complete enumeration, and explicit deletion of domain email
  forwards. `list_page/4` and `list/4` return one page; `list_all/4` starts at
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
- `ReqDnsimple.Webhook` — Retrieve a typed webhook registration or explicitly
  deregister it by integer or numeric-string ID without contacting its callback
  URL or listing registrations. Struct: `id`, `url`, nullable `suppressed_at`.
- `ReqDnsimple.Certificate` — Order typed Let's Encrypt purchases and renewals
  without automatic issuance or deployment; renewal orders preserve distinct
  old and new certificate IDs. Retrieve typed certificate metadata, including
  pending nullable CSR/expiry values; download its server, nullable root, and
  ordered intermediate chain; or retrieve its private key as byte-preserved PEM
  strings without parsing, logging, persisting, or writing files.
- `ReqDnsimple.RegistrantChange` — Start a registrar contact-change request from
  explicit domain/contact identifiers; list one filtered, sorted page or
  explicitly enumerate all matching pages; retrieve one by integer ID; or
  cancel it without polling. Creation returns immediate and pending responses
  without a requirements check. Cancellation returns the typed current request
  when asynchronous or `:ok` when immediate. Registry extended attributes
  retain string keys and values, and the registry lock-lift date may be `nil`.
- `ReqDnsimple.Tld` — Retrieve one TLD's capabilities or its non-paginated,
  typed registry extended-attribute definitions. Arbitrary attribute names and
  option values remain strings, free-text attributes retain empty option lists,
  omitted display titles remain `nil`, and present titles are strings.
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
  from hosted-zone apex NS records and `Zone.update_ns_records/4`.
- `ReqDnsimple.PrimaryServer` — Secondary-DNS primary server creation,
  retrieval, paginated listing, zone linking/unlinking, and explicit deletion. Listing
  supports ordered `id`/`name` sorting: `list_page/3` and `list/3` return one
  page with string-keyed metadata, while `list_all/3` explicitly enumerates
  from page one. Creation requires a name and IP, preserves a supplied integer
  port (including zero), omits an absent port, and performs no reachability or
  follow-up requests. Linking and unlinking require a zone name and send one
  request without looking up or creating either resource. Unlinking retains the
  primary server and zone. Struct: `id`, `account_id`, `name`, `ip`, integer
  `port`, ordered `linked_secondary_zones`, and timestamps. Deletion does not
  unlink zones or perform DNS requests.
- `ReqDnsimple.Service` — Retrieve a global one-click service by sid or ID,
  including typed timestamps and setting definitions, or apply/unapply one on a
  domain. Optional dynamic settings use string keys. Omitted settings send no
  body, while an explicit empty map is preserved. Applying performs no catalog
  lookup or per-record requests; unapplying sends one bodyless request and does
  not delete records individually.
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
