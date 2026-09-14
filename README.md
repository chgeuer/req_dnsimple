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
It currently reconciles 103 supported operations (13 original and 90 added)
with executable contract-test locations and records eight additional published
operations as explicitly `out-of-scope`.

Account-scoped overloads do not add DNSimple endpoints. The inventory's
`scoped_interfaces` covers 95 account-path operations and 137 interface families,
including pagination helpers, root shortcuts, and existing bang functions.
Each entry records its module, function, supported arities, and account-free
arguments. The top-level `client_scope` summarizes construction and account
selection; original explicit-account interfaces and source/contract-test
provenance remain intact.

## Installation

```elixir
def deps do
  [
    {:req_dnsimple, github: "chgeuer/req_dnsimple"}
  ]
end
```

## Quick Start

Runnable, read-only examples and an explicitly opt-in record lifecycle are in
the [sample index](samples/README.md), including every command and required
environment variable. Start with DNSimple sandbox.

### Create an account-scoped client

```elixir
account_id = System.fetch_env!("DNSIMPLE_ACCOUNT_ID")

client =
  ReqDnsimple.new_client(System.fetch_env!("DNSIMPLE_TOKEN"),
    account_id: account_id
  )
```

`new_client/2` requires `account_id` for **both** account tokens (`dnsimple_a_`)
and user tokens (`dnsimple_u_`). Supply a positive integer or an all-digit
positive numeric string, such as `"00123"`; strings are normalized once to an
integer. Missing or malformed configuration raises `ArgumentError` before any
HTTP request. It never discovers an account or checks token permissions.

The result is still a `Req.Request`, not a new wrapper struct. Account scope is
internal Req metadata, preserved by `Req.merge/2`. Other constructor options
configure Req normally, including `base_url`, `headers`, `adapter`, `retry`,
and `receive_timeout`:

```elixir
client =
  ReqDnsimple.new_client(System.fetch_env!("DNSIMPLE_TOKEN"),
    account_id: account_id,
    base_url: "https://api.sandbox.dnsimple.com/v2",
    retry: false,
    receive_timeout: 15_000
  )
  |> Req.merge(headers: [{"x-app", "dns-example"}])
```

You can also pass a zero-arity function for dynamic token resolution. The
function is evaluated for each request and may return either the token string or
`{:bearer, token}`. Neither constructor nor `for_account/2` evaluates it:

```elixir
client =
  ReqDnsimple.new_client(
    fn -> {:bearer, System.fetch_env!("DNSIMPLE_TOKEN")} end,
    account_id: account_id
  )
```

### Scope, explicit overrides, and compatibility

Every existing operation whose second argument is `account_id` also has a
scoped form omitting it. This includes resource modules, list aliases,
`list_page`/`list_all`, applied `Service` operations, root shortcuts,
`ns_records`, and the existing zone-listing bang helpers. Trailing options
remain optional where they were optional before.

```elixir
{:ok, zones} = ReqDnsimple.Zone.list(client, name_like: "example")
{:ok, zone} = ReqDnsimple.Zone.get(client, "example.com")

other_account_id = System.fetch_env!("DNSIMPLE_OTHER_ACCOUNT_ID")
other_client = ReqDnsimple.for_account(client, other_account_id)

# An explicit account overrides scope for this call only.
{:ok, other_zones} = ReqDnsimple.Zone.list(client, other_account_id, per_page: 20)
{:ok, original_zones} = ReqDnsimple.Zone.list(client, per_page: 20)
```

`for_account/2` validates the same positive ID forms and returns an immutable
copy with identical authentication, base URL, transport options, and adapter.
The original is unchanged. Re-scoping sends no HTTP request and does not verify
permissions; DNSimple remains the authority.

For new discovery or global workflows, use `new_unscoped_client/1,2`. It accepts
the same Req transport options, but rejects `account_id` rather than silently
creating a scoped client:

```elixir
discovery =
  ReqDnsimple.new_unscoped_client(fn -> System.fetch_env!("DNSIMPLE_TOKEN") end,
    base_url: "https://api.sandbox.dnsimple.com/v2"
  )

{:error, :missing_account_id} = ReqDnsimple.Zone.list(discovery)
```

A new account-free operation on an unscoped client returns
`{:error, :missing_account_id}` locally, without HTTP or credential resolution.
Bang forms raise `ReqDnsimple.Error` with `reason: :missing_account_id`.
Invalid operation attributes or options retain the established
`NimbleOptions.ValidationError` behavior.

**Compatibility:** `new_client/1` retains its exact legacy unscoped behavior,
including accepting account tokens. Existing explicit-account calls remain
supported on either kind of client:

```elixir
legacy = ReqDnsimple.new_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:ok, zones} = ReqDnsimple.Zone.list(legacy, account_id)
```

Global `whoami/1`, `Account.list/1`, `OAuth.exchange_code/2`, TLD catalogs, and
the global Service catalog do not require scope and also work on scoped clients.
Scoping does not change any operation's established return shape.

### Exchange an OAuth authorization code

Use the same client as a transport configuration; token exchange strips its
inherited Authorization header and does not evaluate a dynamic bearer callback.
Public clients provide a PKCE verifier:

```elixir
{:ok, token} =
  ReqDnsimple.OAuth.exchange_code(client,
    client_id: "your-client-id",
    code: "authorization-code",
    grant_type: "authorization_code",
    code_verifier: String.duplicate("a", 43),
    redirect_uri: "http://127.0.0.1:54321/callback",
    state: "authorization-state"
  )
```

Confidential clients provide `:client_secret` instead of `:code_verifier`.
The result is `{:ok, %ReqDnsimple.OAuth.Token{}}`; `scope` may be `nil`.

### Identify yourself

```elixir
identity = ReqDnsimple.whoami(client)
# => {:user, user} or {:account, account}
```

`whoami/1` selects `{:user, user}` or `{:account, account}` from the non-null
identity in the successful response, independently of token spelling or the
client's authentication configuration. If both identities are present or both
are absent, it returns `{:unknown_token, full_response_body}`.

### Discover an account explicitly

An account token can identify its account with an explicit `whoami/1` request:

```elixir
discovery = ReqDnsimple.new_unscoped_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:account, %{"id" => discovered_id}} = ReqDnsimple.whoami(discovery)
client = ReqDnsimple.for_account(discovery, discovered_id)
```

For a user token, list accessible accounts, then select an account deliberately:

```elixir
discovery = ReqDnsimple.new_unscoped_client(System.fetch_env!("DNSIMPLE_TOKEN"))
accounts = ReqDnsimple.Account.list(discovery)
# Account.list/1 returns a bare list, not {:ok, accounts}.
Enum.map(accounts, & &1.id)

# Set this to an account selected by the user/application, not the first result.
client = ReqDnsimple.for_account(discovery, System.fetch_env!("DNSIMPLE_ACCOUNT_ID"))
```

Do not choose `hd(accounts)` automatically, and never treat `user.id` from
`whoami/1` as an account ID. Prefixes are guidance only; the identity response
and DNSimple's permission checks are authoritative. The
[discovery samples](samples/README.md#read-only-programs) handle error results
and enforce explicit user-account selection.

`Account.name` is optional because older responses may omit it. DNSimple's
account examples and official SDK include the field even though its OpenAPI
schema does not.

### List zones

```elixir
{:ok, zones} = ReqDnsimple.Zone.list(client)
# => {:ok, [%ReqDnsimple.Zone{name: "example.com", ...}, ...]}
```

Filter and sort:

```elixir
{:ok, zones} = ReqDnsimple.Zone.list(client,
  name_like: "example",
  sort: [:id, name: :asc]
)
```

Use scoped `list_page/1,2` when pagination metadata is needed, or `list_all/1,2`
to fetch every page from page one:

```elixir
{:ok, {zones, pagination}} = ReqDnsimple.Zone.list_page(client, per_page: 50)
{:ok, all_zones} = ReqDnsimple.Zone.list_all(client, name_like: "example")
```

`Contact` and `BillingCharge` provide the same scoped `list_page/1,2` and
`list_all/1,2` interfaces. `ZoneRecord` provides `list_page/2,3` and
`list_all/2,3`, with the zone argument retained. Explicit-account forms remain
available, as listed in the API catalog below. `list_all`
preserves filters, sorting, and `per_page`, but rejects `page` because complete
enumeration always begins at page one.

### Get a zone

```elixir
{:ok, zone} = ReqDnsimple.Zone.get(client, "example.com")
# => {:ok, %ReqDnsimple.Zone{name: "example.com", active: true, ...}}
```

This sends one bodyless request and returns the complete zone, including its
reverse, secondary, activation, and nullable last-transfer fields.

### Query DNS analytics

DNS analytics retain the endpoint's tabular headers, rows, and echoed query
metadata:

```elixir
{:ok, {result, pagination}} =
  ReqDnsimple.DnsAnalytics.list_page(client,
    start_date: "2026-09-01",
    end_date: "2026-09-02",
    groupings: [:date, :zone_name],
    sort: [date: :asc, volume: :desc],
    page: 1,
    per_page: 1000
  )
```

Scoped `query/2` is a single-page alias. `list_all/2` explicitly enumerates from page
one and returns one `%ReqDnsimple.DnsAnalytics.Result{}` with compatible rows
combined in server order and the first page's query retained as provenance.

### Activate DNS service for a zone

The mutation snippets below illustrate individual APIs; they can change live
DNS or incur charges. For an executable, guarded mutation example, use the
[opt-in sandbox record lifecycle](samples/README.md#opt-in-mutation-one-record-lifecycle).

```elixir
{:ok, zone} = ReqDnsimple.Zone.activate(client, "example.com")
# => {:ok, %ReqDnsimple.Zone{active: true, ...}}
```

Activation sends one bodyless request and returns the resulting zone. DNSimple
may renew an expired domain subscription and charge the account during
activation. The client does not preflight billing, register a domain, or make
follow-up requests.

### Deactivate DNS service for a zone

```elixir
{:ok, zone} = ReqDnsimple.Zone.deactivate(client, "example.com")
# => {:ok, %ReqDnsimple.Zone{active: false, ...}}
```

Deactivation sends one bodyless request and stops DNS resolution without
deleting the zone, domain, or records. The client performs no preflight,
follow-up request, or additional mutation.

### Manage DNS records

**List records for a zone:**

```elixir
{:ok, {records, pagination}} = ReqDnsimple.ZoneRecord.list(
  client, "example.com",
  type: "A",
  sort: [:id, name: :asc]
)
```

**Create a record:**

```elixir
{:ok, record} = ReqDnsimple.ZoneRecord.create(
  client, "example.com",
  name: "www", type: "A", content: "93.184.215.14", ttl: 3600
)
```

The equivalent scoped `ReqDnsimple.create_zone_record/3` helper and
`ReqDnsimple.ZoneRecord.create/3` accept the same attributes as their legacy
`/4` forms. Both scoped and explicit-account arities expose full attribute
documentation for Livebook code help; display it without making a request:

```elixir
require IEx.Helpers
IEx.Helpers.h(ReqDnsimple.create_zone_record/3)
```

After changing a local path dependency, restart the Livebook runtime and
re-evaluate the setup with `Mix.install(..., force: true)` once to refresh its
compiled documentation.

**Update a record:**

```elixir
{:ok, record} = ReqDnsimple.ZoneRecord.update(
  client, "example.com", record_id,
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
  ReqDnsimple.ZoneRecord.batch_change(client, "example.com",
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
:ok = ReqDnsimple.ZoneRecord.delete(client, "example.com", record_id)
```

### Update hosted-zone NS records

```elixir
{:ok, ns_records} =
  ReqDnsimple.Zone.update_ns_records(client, "example.com",
    ns_names: ["ns1.example.com", "ns2.example.com"],
    ns_set_ids: [name_server_set_id]
  )
```

Pass `ns_names`, `ns_set_ids`, or both; explicit empty lists are sent unchanged.
The call replaces apex NS records in one request without first reading or
merging existing records. To retain vanity name-server configuration, include
its names or sets in the call. This hosted-zone operation does not change the
domain's registrar delegation.

### Enable and disable vanity name servers

```elixir
{:ok, vanity_name_servers} =
  ReqDnsimple.VanityNameServer.enable(client, "example.com")
```

Enabling sends one bodyless request and returns the typed vanity A and AAAA
records created by DNSimple. The API can reject the request when the account's
plan or payment state does not permit vanity name servers.

```elixir
:ok = ReqDnsimple.VanityNameServer.disable(client, "example.com")
```

Disabling sends one bodyless request to remove the domain's vanity A and AAAA
configuration. Neither operation changes registrar delegation, and disabling
does not delete records individually.

### List, register, retrieve, or deregister webhook endpoints

```elixir
{:ok, webhooks} =
  ReqDnsimple.Webhook.list(client, sort: [id: :asc])
```

Webhook listing returns the complete, non-paginated collection and supports
ordered `id` sorting.

```elixir
{:ok, webhook} =
  ReqDnsimple.Webhook.create(
    client,
    url: "https://receiver.example/events?source=dnsimple"
  )
```

Webhook registration requires an absolute HTTPS callback URL and sends it
unchanged in one POST request without contacting or probing the callback.

```elixir
{:ok, webhook} = ReqDnsimple.Webhook.get(client, webhook_id)
# => {:ok, %ReqDnsimple.Webhook{url: "https://receiver.example/events", suppressed_at: nil}}
```

Webhook retrieval returns the registered callback URL and its nullable
suppression timestamp without contacting the callback URL.

```elixir
:ok = ReqDnsimple.Webhook.delete(client, webhook_id)
```

Listing, retrieval, and deletion send one bodyless request. Retrieval and
deletion accept an integer or numeric-string webhook ID. None of these
operations contacts the callback URL or inspects deliveries.

### Get a zone file

```elixir
{:ok, zone_file} = ReqDnsimple.Zone.get_zone_file(client, "example.com")
# => {:ok, "$ORIGIN example.com.\n$TTL 3600\n..."}
```

### Check zone distribution

```elixir
{:ok, true} = ReqDnsimple.Zone.check_zone_distribution(client, "example.com")
```

### Check zone record distribution

```elixir
{:ok, false} =
  ReqDnsimple.ZoneRecord.check_distribution(client, "example.com", record_id)
```

### Order and retrieve certificates

```elixir
{:ok, %ReqDnsimple.Certificate.Purchase{} = purchase} =
  ReqDnsimple.Certificate.purchase_letsencrypt(
    client,
    "example.com",
    auto_renew: false,
    name: "api",
    alternate_names: ["docs.example.com"],
    signature_algorithm: "RSA"
  )
```

Without attributes, DNSimple's server defaults cover `www`. Custom names,
subject-alternative names, and wildcards depend on the account plan. Ordering
returns separate purchase and certificate IDs; it does not issue, download, or
deploy the certificate automatically.

```elixir
{:ok, %ReqDnsimple.Certificate.Renewal{} = renewal} =
  ReqDnsimple.Certificate.purchase_letsencrypt_renewal(
    client,
    "example.com",
    certificate_id,
    auto_renew: false,
    signature_algorithm: "RSA"
  )
```

Renewal ordering returns distinct old and new certificate IDs and does not
issue or deploy the replacement certificate automatically. Omitting attributes
leaves renewal defaults to DNSimple.

```elixir
{:ok, %ReqDnsimple.Certificate{state: "requesting"} = certificate} =
  ReqDnsimple.Certificate.issue_letsencrypt(
    client,
    "example.com",
    purchase.certificate_id
  )
```

Issuance uses the certificate ID returned by the purchase, not the purchase
order ID. It sends one bodyless request and returns immediately without polling,
downloading, or deploying the certificate.

```elixir
{:ok, %ReqDnsimple.Certificate{state: "requesting"} = replacement} =
  ReqDnsimple.Certificate.issue_letsencrypt_renewal(
    client,
    "example.com",
    renewal.old_certificate_id,
    renewal.id
  )
```

Renewal issuance binds the original certificate ID before the renewal order ID.
It returns the replacement certificate, which can have a different ID, without
creating another renewal order or waiting for issuance to complete.

```elixir
{:ok, {certificates, pagination}} =
  ReqDnsimple.Certificate.list_page(
    client,
    "example.com",
    sort: [expiration: :asc, common_name: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_certificates} =
  ReqDnsimple.Certificate.list_all(
    client,
    "example.com",
    sort: [id: :desc],
    per_page: 100
  )
```

Certificate listing preserves the server's descending-ID order when sorting is
omitted. Scoped `list_page/3` (and its `list/3` alias) returns one page with
pagination; `list_all/3` explicitly enumerates from page one.

```elixir
{:ok, %ReqDnsimple.Certificate{} = certificate} =
  ReqDnsimple.Certificate.get(client, "example.com", certificate_id)
```

Certificate metadata includes its issuance state, alternate names, renewal
setting, and typed creation/update and nullable expiry values.

```elixir
{:ok, %ReqDnsimple.Certificate.Download{} = bundle} =
  ReqDnsimple.Certificate.download(client, "example.com", certificate_id)
```

The bundle contains the server certificate, nullable root certificate, and
ordered intermediate certificate chain as PEM strings. The strings are
preserved exactly and are not parsed or written to files.

```elixir
{:ok, %ReqDnsimple.Certificate.PrivateKey{private_key: private_key}} =
  ReqDnsimple.Certificate.get_private_key(client, "example.com", certificate_id)
```

The private key PEM is likewise preserved byte-for-byte and is not parsed,
logged, persisted, or written to a file.

### Billing charges

```elixir
{:ok, charges} = ReqDnsimple.BillingCharge.list(client,
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
{:ok, contact} =
  ReqDnsimple.Contact.create(client,
    first_name: "Test",
    last_name: "Contact",
    email: "contact@example.test",
    phone: "+12025550123",
    address1: "1 Example Street",
    city: "Roma",
    state_province: "RM",
    postal_code: "00100",
    country: "IT"
  )

{:ok, contact} =
  ReqDnsimple.Contact.update(client, contact_id,
    label: "",
    address2: nil,
    fax: nil
  )

{:ok, contacts} = ReqDnsimple.Contact.list(client, sort: [label: :asc])
{:ok, contact}  = ReqDnsimple.Contact.get(client, contact_id)
:ok = ReqDnsimple.Contact.delete(client, contact_id)
```

### DNS templates

```elixir
{:ok, {templates, pagination}} =
  ReqDnsimple.Template.list_page(client,
    sort: [id: :asc, name: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_templates} =
  ReqDnsimple.Template.list_all(client, sort: [sid: :asc])

{:ok, template} =
  ReqDnsimple.Template.update(client, "offline-template",
    description: ""
  )
```

Scoped `list_page/2` and its `list/2` alias fetch one page with string-keyed
pagination metadata. `list_all/2` explicitly enumerates from page one while
retaining sorting and `per_page`. `update/3` patches only the supplied metadata
and uses the caller's original template identifier for the request path.

### Domains

```elixir
{:ok, hosted_domain} =
  ReqDnsimple.Domain.create(client, name: "example.test")

{:ok, domain} = ReqDnsimple.Domain.get(client, "example.com")

{:ok, {domains, pagination}} =
  ReqDnsimple.Domain.list_page(client,
    name_like: "example",
    sort: [name: :asc],
    per_page: 30
  )

{:ok, all_domains} =
  ReqDnsimple.Domain.list_all(client, registrant_id: 42)
```

Domain creation adds the named domain and its hosted zone in one request and
returns a typed `ReqDnsimple.Domain` struct. DNSimple may charge for the DNS
service subscription. It does not register or purchase the domain, change
delegation, verify ownership, or issue a separate zone-creation request.
Retrieval accepts a name or integer ID and returns registration state, privacy,
renewal, and nullable expiry metadata. Scoped `list_page/2` and its `list/2`
alias return one typed page with string-keyed pagination metadata; `list_all/2`
explicitly enumerates from page one while retaining `name_like` and
`registrant_id` filters, `id`/`name`/`expiration` sorting, and page size.

### TLD capabilities and extended attributes

```elixir
{:ok, {tlds, pagination}} =
  ReqDnsimple.Tld.list_page(client, sort: [tld: :asc], per_page: 30)

{:ok, all_tlds} = ReqDnsimple.Tld.list_all(client, sort: [tld: :asc])

{:ok, attributes} = ReqDnsimple.Tld.list_extended_attributes(client, "co.uk")
```

The paginated list returns typed TLD capability values and string-keyed
pagination metadata. `list/2` is a single-page alias, while `list_all/2`
explicitly enumerates from page one and retains TLD sorting and page size.
Numeric-string name-server bounds are normalized to integers and omitted bounds
remain `nil`. The non-paginated extended-attribute result contains typed
`ReqDnsimple.Tld.ExtendedAttribute` values and their typed options. Registry
attribute names and values remain strings, free-text attributes retain
`options: []`, and an omitted display title is `nil`; a present title is always
a string. This retrieval does not submit registrant data or initiate a
registration or transfer.

### Registrar operations

Check a domain before registration or transfer:

```elixir
{:ok, %ReqDnsimple.Registrar.CheckResult{} = result} =
  ReqDnsimple.Registrar.check(client, "example.com")
```

The registrar check is intended for low-volume interactive use and has a
stricter rate limit than most DNSimple endpoints. It reports availability,
premium status, and the optional trustee flag without using the paid Domain
Research API, registering the domain, or retrying a rate-limited request.

Retrieve current registration and lifecycle prices without initiating a
purchase:

```elixir
{:ok, %ReqDnsimple.Registrar.Prices{} = prices} =
  ReqDnsimple.Registrar.get_prices(client, "example.com")
```

Registration, renewal, transfer, restore, and trustee prices remain JSON
numbers. Optional transfer and trustee prices are `nil` when omitted.

Submit a registration for an existing contact without hidden preflight requests:

```elixir
{:ok, %ReqDnsimple.Registrar.Registration{} = registration} =
  ReqDnsimple.Registrar.register(
    client,
    "example.com",
    registrant_id: contact_id,
    whois_privacy: false,
    auto_renew: false,
    trustee: false,
    extended_attributes: %{"uk_legal_type" => "IND"},
    premium_price: "12.00",
    linked_provider: "provider"
  )
```

Only `registrant_id` is required. Omitted settings remain omitted, explicit
false values and string-keyed extended attributes are preserved, and premium
prices remain exact strings. DNSimple determines registration, service,
trustee, and premium charges; callers must confirm any premium price before
calling. Both immediate and asynchronous responses return the typed registration
job without availability, price, contact, hosted-domain, or polling requests.

Submit an inbound transfer for an existing contact without hidden preflight
requests:

```elixir
{:ok, %ReqDnsimple.Registrar.Transfer{} = transfer} =
  ReqDnsimple.Registrar.transfer(
    client,
    "example.com",
    registrant_id: contact_id,
    auth_code: "transfer-code",
    whois_privacy: false,
    auto_renew: false,
    trustee: false,
    extended_attributes: %{"us_nexus" => "C11"},
    premium_price: "12.00"
  )
```

Only `registrant_id` is universally required; authorization codes and extended
attributes are TLD-dependent. Omitted settings remain omitted, explicit false
values and string-keyed extended attributes are preserved, and premium prices
remain exact strings. Both immediate and asynchronous responses return the
typed transfer job without TLD, price, unlock, transfer-out authorization, or
polling requests.

Retrieve the current transfer-lock state without changing it:

```elixir
{:ok, %ReqDnsimple.Registrar.TransferLock{enabled: enabled}} =
  ReqDnsimple.Registrar.get_transfer_lock(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless request,
and returns both enabled and disabled states in the typed resource without a
domain lookup or mutation.

Explicitly enable the transfer lock without a domain lookup or other registrar
operation:

```elixir
{:ok, %ReqDnsimple.Registrar.TransferLock{enabled: true}} =
  ReqDnsimple.Registrar.enable_transfer_lock(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless POST, and
returns the resulting typed transfer-lock state.

Explicitly disable the transfer lock without requesting an authorization code
or initiating a transfer:

```elixir
{:ok, %ReqDnsimple.Registrar.TransferLock{enabled: false}} =
  ReqDnsimple.Registrar.disable_transfer_lock(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless DELETE,
and returns the resulting typed transfer-lock state.

Enable or disable future automatic renewal without renewing or otherwise
modifying the domain:

```elixir
:ok = ReqDnsimple.Registrar.enable_auto_renewal(client, "example.com")
:ok = ReqDnsimple.Registrar.disable_auto_renewal(client, "example.com")
```

Both operations accept a domain name or integer ID, send one bodyless request,
and return registry or TLD refusal responses as explicit errors.

Enable WHOIS privacy without a price lookup or purchase preflight:

```elixir
{:ok, %ReqDnsimple.Registrar.WhoisPrivacy{} = privacy} =
  ReqDnsimple.Registrar.enable_whois_privacy(client, "example.com")
```

The operation accepts a domain name or integer ID and returns the typed privacy
state for modern HTTP 200 and legacy HTTP 201 responses. It sends one bodyless
request and does not promise or initiate a separate one-year purchase. Legacy
payment failures, including HTTP 402, are returned as explicit errors.

Disable WHOIS privacy without a lookup, refund, or other registrar operation:

```elixir
{:ok, %ReqDnsimple.Registrar.WhoisPrivacy{enabled: false} = privacy} =
  ReqDnsimple.Registrar.disable_whois_privacy(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless DELETE,
and returns the resulting typed privacy state.

Submit a renewal without a price lookup or follow-up polling:

```elixir
{:ok, %ReqDnsimple.Registrar.Renewal{} = renewal} =
  ReqDnsimple.Registrar.renew(
    client,
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
    "example.com",
    premium_price: "109.00"
  )
```

The premium price is optional and remains an exact string when supplied. Both
immediate and asynchronous responses return the typed restore job. DNSimple
determines restore charges and eligibility; payment and registry refusals are
returned as explicit errors without an automatic renewal, purchase, or poll.

Retrieve the current registrar delegation without reading hosted-zone records:

```elixir
{:ok, ["ns1.example.com", "ns2.example.com"]} =
  ReqDnsimple.Registrar.get_delegation(client, "example.com")
```

The operation accepts a domain name or integer ID and returns the ordered
name-server hostnames exactly as DNSimple supplies them.

```elixir
{:ok, name_servers} =
  ReqDnsimple.Registrar.change_delegation(
    client,
    "example.com",
    name_servers: ["ns1.example.com", "ns2.example.com"]
  )
```

Delegation changes accept a domain name or integer ID and replace the registrar
name-server list in one request. The supplied order and explicit empty lists are
preserved; the wrapper does not fetch or merge the old delegation. This is
separate from hosted-zone apex NS records and `Zone.update_ns_records/3,4`.

### Registrant changes

```elixir
{:ok, %ReqDnsimple.RegistrantChange{} = change} =
  ReqDnsimple.RegistrantChange.create(
    client,
    domain_id: "example.test",
    contact_id: "11",
    extended_attributes: %{
      "x-fi-registrant-idnumber" => "fake-offline-id"
    }
  )

{:ok, %ReqDnsimple.RegistrantChange{} = change} =
  ReqDnsimple.RegistrantChange.get(client, registrant_change_id)

{:ok, {changes, pagination}} =
  ReqDnsimple.RegistrantChange.list_page(
    client,
    sort: [id: :asc],
    state: "completed",
    domain_id: "100",
    contact_id: "11",
    page: 2,
    per_page: 30
  )

{:ok, all_pending_changes} =
  ReqDnsimple.RegistrantChange.list_all(client, state: "pending")

{:ok, %ReqDnsimple.RegistrantChange{state: "cancelling"}} =
  ReqDnsimple.RegistrantChange.cancel(client, registrant_change_id)
```

Registrant-change creation accepts domain/contact integer IDs or string forms,
including a domain name, and returns either an immediately completed or pending
request without polling. Creation preserves omitted versus explicitly empty
registry extended attributes and performs no requirements check. Retrieval
returns the current state, dynamic registry extended attributes with string
keys, and typed date/timestamp fields. A pending registry lock-lift date remains
`nil`. Cancellation returns the typed current request for an asynchronous
cancellation or `:ok` when cancellation completes immediately; it does not poll.

### Domain Research

```elixir
{:ok, research} =
  ReqDnsimple.DomainResearch.get_status(client, domain: "example.com")
```

Domain Research is a paid service requiring the `domain_research_read` OAuth
scope. It returns the request ID, researched domain, availability
(`"available"`, `"unavailable"`, or `"unknown"`), and any research errors in a
typed `ReqDnsimple.DomainResearch` struct. It uses the dedicated research
endpoint, does not fall back to a registrar availability check, and does not
automatically retry quota responses.

### Domain pushes

```elixir
source_client =
  ReqDnsimple.for_account(client, System.fetch_env!("DNSIMPLE_SOURCE_ACCOUNT_ID"))

target_client =
  ReqDnsimple.for_account(client, System.fetch_env!("DNSIMPLE_TARGET_ACCOUNT_ID"))

{:ok, push} =
  ReqDnsimple.DomainPush.initiate(
    source_client,
    domain,
    new_account_identifier: target_account_identifier
  )

{:ok, {pushes, pagination}} =
  ReqDnsimple.DomainPush.list_page(target_client, page: 1, per_page: 30)

{:ok, all_pushes} = ReqDnsimple.DomainPush.list_all(target_client)
:ok = ReqDnsimple.DomainPush.accept(target_client, push_id, contact_id: contact_id)
:ok = ReqDnsimple.DomainPush.reject(target_client, push_id)
```

Initiating a push is source-account scoped and requires exactly one target:
`:new_account_identifier`, or the deprecated `:new_account_email`. Pending-push
listing and acceptance are target-account scoped. Scoped `list_page/2` and
`list/2` return one typed page with string-keyed pagination metadata; `list_all/2`
deliberately enumerates from page one and accepts only `:per_page`. Accepting a
push sends exactly one request using the selected target-account contact.
Rejecting a push sends a bodyless request and does not delete the source domain.
None of these operations performs a preflight request.

### DNSSEC

```elixir
{:ok, dnssec} = ReqDnsimple.Dnssec.get(client, "example.com")
{:ok, dnssec} = ReqDnsimple.Dnssec.enable(client, "example.com")
:ok = ReqDnsimple.Dnssec.disable(client, "example.com")
```

Retrieval returns the enabled and active states separately, with typed creation
and update timestamps.

For domains registered with DNSimple, enabling DNSSEC includes registry
delegation-signer submission. Hosted-only domains require the caller to
coordinate delegation-signer records with the registrar.

For hosted-only domains, remove registry delegation-signer records before
disabling DNSSEC. This operation does not remove those records or prompt for
confirmation.

### Delegation-signer records

```elixir
{:ok, delegation_signer_record} =
  ReqDnsimple.DelegationSignerRecord.create(
    client,
    "example.com",
    algorithm: "13",
    digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    digest_type: "2",
    keytag: "12345"
  )

{:ok, delegation_signer_record} =
  ReqDnsimple.DelegationSignerRecord.get(
    client,
    "example.com",
    ds_record_id
  )

{:ok, {delegation_signer_records, pagination}} =
  ReqDnsimple.DelegationSignerRecord.list_page(
    client,
    "example.com",
    sort: [id: :asc, created_at: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_delegation_signer_records} =
  ReqDnsimple.DelegationSignerRecord.list_all(
    client,
    "example.com",
    sort: [created_at: :desc]
  )

:ok =
  ReqDnsimple.DelegationSignerRecord.delete(
    client,
    "example.com",
    ds_record_id
  )
```

Creation accepts a string algorithm with either a complete DS tuple or KEY
`public_key`, and returns a typed `ReqDnsimple.DelegationSignerRecord`. DS and
KEY proof fields that do not apply to the returned representation are `nil`.
Scoped `list_page/3` and its `list/3` alias return one typed page with string-keyed
pagination metadata; `list_all/3` explicitly enumerates from page one while
retaining `id`/`created_at` sorting and page size. Deletion removes only the
selected registry delegation-signer record. It does not disable DNSSEC or
delete hosted-zone records.

### Email forwards

```elixir
{:ok, email_forward} =
  ReqDnsimple.EmailForward.create(
    client,
    "example.com",
    alias_name: "support",
    destination_email: "recipient@example.test"
  )

{:ok, email_forward} =
  ReqDnsimple.EmailForward.get(client, "example.com", email_forward_id)

{:ok, {email_forwards, pagination}} =
  ReqDnsimple.EmailForward.list_page(
    client,
    "example.com",
    sort: [id: :asc, alias_email: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_email_forwards} =
  ReqDnsimple.EmailForward.list_all(
    client,
    "example.com",
    sort: [destination_email: :asc]
  )

:ok = ReqDnsimple.EmailForward.delete(client, "example.com", email_forward_id)
```

Creation sends the local-part `alias_name` unchanged and returns a typed
`ReqDnsimple.EmailForward` with its full alias email, destination email,
activation state, and timestamps. The returned `alias_email` is distinct from
the creation input. Scoped `list_page/3` and its `list/3` alias return one typed page
with string-keyed pagination metadata; `list_all/3` explicitly enumerates from
page one while retaining `id`/`alias_email`/`destination_email` sorting and page
size. Creation does not provision DNS records or send a test email. Deletion
removes only the selected email forward and does not modify the domain's MX
records.

### Secondary-DNS primary servers

```elixir
{:ok, primary_server} =
  ReqDnsimple.PrimaryServer.create(
    client,
    name: "Primary",
    ip: "192.0.2.1",
    port: 5353
  )

{:ok, primary_server} = ReqDnsimple.PrimaryServer.get(client, primary_server_id)

{:ok, {primary_servers, pagination}} =
  ReqDnsimple.PrimaryServer.list_page(
    client,
    sort: [id: :asc, name: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_primary_servers} =
  ReqDnsimple.PrimaryServer.list_all(client, sort: [name: :asc])

{:ok, primary_server} =
  ReqDnsimple.PrimaryServer.link(
    client,
    primary_server_id,
    zone: "secondary.example.test"
  )

{:ok, primary_server} =
  ReqDnsimple.PrimaryServer.unlink(
    client,
    primary_server_id,
    zone: "secondary.example.test"
  )

:ok = ReqDnsimple.PrimaryServer.delete(client, primary_server_id)
```

The returned `ReqDnsimple.PrimaryServer` includes its IP, integer port, and the
ordered list of linked secondary-zone names. Creation requires a name and IP,
sends a supplied integer port unchanged, and leaves an omitted port to the API.
It performs no reachability check or follow-up request. Retrieval makes no
zone-transfer or reachability requests. Scoped `list_page/2` and its `list/2`
alias return one typed page with string-keyed pagination metadata; `list_all/2`
explicitly enumerates from page one while retaining sorting and page size.
Listing supports ordered `id` and `name` sorting. Linking sends the required
secondary-zone name in one request without looking up or creating either
resource. Unlinking removes only that zone association while retaining both
resources and returns the updated primary server. Deletion removes only the
selected primary-server configuration; it does not unlink zones or perform DNS
requests.

### Secondary DNS zones

```elixir
{:ok, zone} =
  ReqDnsimple.SecondaryZone.create(
    client,
    name: "secondary.example.test"
  )
```

Creation sends one `POST` request and returns the existing `ReqDnsimple.Zone`
struct with `secondary: true`. A response may omit `active`, in which case it
remains `nil`; a null `last_transferred_at` also remains `nil`. DNSimple may
require ownership verification and a subscription. Those failures are returned
without changing delegation, creating primary servers, or making preflight or
follow-up requests.

### One-click services

```elixir
{:ok, service} = ReqDnsimple.Service.get(client, "service-sid")

{:ok, {catalog, pagination}} =
  ReqDnsimple.Service.list_page(
    client,
    sort: [id: :asc, sid: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_catalog_services} =
  ReqDnsimple.Service.list_all(client, sort: [sid: :asc], per_page: 100)

{:ok, {services, pagination}} =
  ReqDnsimple.Service.list_page_applied(
    client,
    "example.com",
    page: 2,
    per_page: 30
  )

{:ok, all_services} =
  ReqDnsimple.Service.list_all_applied(client, "example.com", per_page: 100)

:ok = ReqDnsimple.Service.apply(client, "example.com", "service-sid")

:ok =
  ReqDnsimple.Service.apply(
    client,
    "example.com",
    "service-sid",
    settings: %{"app" => "my-app"}
  )

:ok = ReqDnsimple.Service.unapply(client, "example.com", "service-sid")
```

Service retrieval accepts a sid or integer ID and returns a typed
`ReqDnsimple.Service` with typed nested setting definitions and timestamps.
`list_page/2` and its `list/2` alias return one typed page of the global
catalog, accepting ordered `id`/`sid` sorting and pagination options.
`list_all/2` explicitly enumerates the catalog from page one while preserving
sorting and `per_page`, and rejects an explicit `page`.
Scoped `list_page_applied/3` and its `list_applied/3` alias return one typed page of
services applied to a domain with string-keyed pagination metadata.
`list_all_applied/3` explicitly enumerates from page one, preserves `per_page`,
and rejects an explicit `page`.
Omitting `settings` sends no request body; an explicit empty map sends
`{"settings": {}}`. Setting names remain strings. Applying a service performs
one request without fetching the service or creating records individually.
Unapplying a service performs one bodyless request without fetching the service
or deleting records individually.

## Convenience Delegates

The top-level `ReqDnsimple` module provides shorthand delegates for common operations:

```elixir
# These are equivalent:
ReqDnsimple.list_zones(client, name_like: "example", per_page: 20)
ReqDnsimple.Zone.list(client, name_like: "example", per_page: 20)

ReqDnsimple.create_zone_record(client, "example.com", attrs)
ReqDnsimple.ZoneRecord.create(client, "example.com", attrs)

ReqDnsimple.list_contacts(client, sort: [label: :asc], per_page: 20)
ReqDnsimple.Contact.list(client, sort: [label: :asc], per_page: 20)

ReqDnsimple.list_billing_charges(client, sort: [invoiced: :desc], per_page: 20)
ReqDnsimple.BillingCharge.list(client, sort: [invoiced: :desc], per_page: 20)
```

Root `list_zones`, `list_zones!`, `list_contacts`, and `list_billing_charges`
accept the same options as their resource-module counterparts, in both scoped
and explicit-account forms. All existing explicit-account shortcuts still work.

`ReqDnsimple.ns_records/2,3` is a read-only convenience for enumerating every
apex (`name=""`) NS record in a zone through the zone-record collection. These
records describe the zone apex; they are distinct from registrar delegation and
from the separate API that explicitly replaces a zone's NS records.

## API Modules

This catalog describes the currently exported modules and operations; it is not
a claim that every published DNSimple endpoint is wrapped.
Arity lists include both account-scoped and legacy explicit-account forms.
For account operations, omit only the second (`account_id`) argument when using
a scoped client; optional trailing options remain available. Global operations
do not gain an account argument.

| Module | DNSimple API | Operations |
|--------|-------------|------------|
| `ReqDnsimple` | Client, `/whoami`, apex NS record enumeration, result handling | `new_client/1,2`, `new_unscoped_client/1,2`, `for_account/2`, `whoami/1`, `token_type/1`, `ns_records/2,3`, `list_zones/1,2,3`, `list_zones!/1,2,3`, `list_contacts/1,2,3`, `list_billing_charges/1,2,3`, `unwrap!/1` |
| `ReqDnsimple.OAuth` | `/oauth/access_token` | `exchange_code/2` |
| `ReqDnsimple.Account` | `/accounts` | `list/1` |
| `ReqDnsimple.Zone` | `/zones` | `list/1,2,3`, `list!/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `get/2,3`, `activate/2,3`, `deactivate/2,3`, `update_ns_records/3,4`, `get_zone_file/2,3`, `check_zone_distribution/2,3` |
| `ReqDnsimple.ZoneRecord` | `/zones/:zone/records`, `/zones/:zone/batch` | `list/2,3,4`, `list_page/2,3,4`, `list_all/2,3,4`, `get/3,4`, `create/3,4`, `update/4,5`, `delete/3,4`, `check_distribution/3,4`, `batch_change/3,4` |
| `ReqDnsimple.BillingCharge` | `/billing/charges` | `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3` |
| `ReqDnsimple.Contact` | `/contacts` | `create/2,3`, `update/3,4`, `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `get/2,3`, `delete/2,3` |
| `ReqDnsimple.Domain` | `/domains`, `/domains/:domain` | `create/2,3`, `get/2,3`, `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `delete/2,3` |
| `ReqDnsimple.DomainResearch` | `/domains/research/status` | `get_status/2,3` |
| `ReqDnsimple.DnsAnalytics` | `/dns_analytics` | `query/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3` |
| `ReqDnsimple.Dnssec` | `/domains/:domain/dnssec` | `get/2,3`, `enable/2,3`, `disable/2,3` |
| `ReqDnsimple.DelegationSignerRecord` | `/domains/:domain/ds_records[/:ds_record]` | `create/3,4`, `get/3,4`, `list/2,3,4`, `list_page/2,3,4`, `list_all/2,3,4`, `delete/3,4` |
| `ReqDnsimple.EmailForward` | `/domains/:domain/email_forwards[/:email_forward]` | `create/3,4`, `list/2,3,4`, `list_page/2,3,4`, `list_all/2,3,4`, `get/3,4`, `delete/3,4` |
| `ReqDnsimple.DomainPush` | `/domains/:domain/pushes`, `/pushes[/:push]` | `initiate/3,4`, `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `accept/3,4`, `reject/2,3` |
| `ReqDnsimple.VanityNameServer` | `/vanity/:domain` | `enable/2,3`, `disable/2,3` |
| `ReqDnsimple.Registrar` | `/registrar/domains/:domain` | `check/2,3`, `get_prices/2,3`, `get_transfer_lock/2,3`, `enable_transfer_lock/2,3`, `disable_transfer_lock/2,3`, `authorize_transfer_out/2,3`, `disable_auto_renewal/2,3`, `enable_auto_renewal/2,3`, `enable_whois_privacy/2,3`, `disable_whois_privacy/2,3`, `register/3,4`, `transfer/3,4`, `renew/2,3,4`, `restore/2,3,4`, `get_delegation/2,3`, `change_delegation/3,4` |
| `ReqDnsimple.RegistrantChange` | `/registrar/registrant_changes[/:registrant_change]` | `create/2,3`, `get/2,3`, `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `cancel/2,3` |
| `ReqDnsimple.Certificate` | `/domains/:domain/certificates` | `purchase_letsencrypt/2,3,4`, `purchase_letsencrypt_renewal/3,4,5`, `issue_letsencrypt/3,4`, `issue_letsencrypt_renewal/4,5`, `list/2,3,4`, `list_page/2,3,4`, `list_all/2,3,4`, `get/3,4`, `download/3,4`, `get_private_key/3,4` |
| `ReqDnsimple.Tld` | `/tlds[/:tld]`, `/tlds/:tld/extended_attributes` | `get/2`, `list/1`, `list/2`, `list_page/1`, `list_page/2`, `list_all/1`, `list_all/2`, `list_extended_attributes/2` |
| `ReqDnsimple.PrimaryServer` | `/secondary_dns/primaries` | `create/2,3`, `get/2,3`, `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `link/3,4`, `unlink/3,4`, `delete/2,3`, `from_json/1` |
| `ReqDnsimple.SecondaryZone` | `/secondary_dns/zones` | `create/2,3` |
| `ReqDnsimple.Service` | `/services[/:service]`, `/domains/:domain/services[/:service]` | `get/2`, `list/1,2`, `list_page/1,2`, `list_all/1,2`, `list_applied/2,3,4`, `list_page_applied/2,3,4`, `list_all_applied/2,3,4`, `apply/3,4,5`, `unapply/3,4` |
| `ReqDnsimple.Template` | `/templates[/:template]`, `/domains/:domain/templates/:template` | `create/2,3`, `get/2,3`, `update/3,4`, `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `apply/3,4`, `delete/2,3` |
| `ReqDnsimple.TemplateRecord` | `/templates/:template/records[/:record]` | `create/3,4`, `get/3,4`, `list/2,3,4`, `list_page/2,3,4`, `list_all/2,3,4`, `delete/3,4` |
| `ReqDnsimple.Webhook` | `/webhooks[/:webhook]` | `list/1,2,3`, `create/2,3`, `get/2,3`, `delete/2,3` |
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
- **Missing account scope** on new account-free calls returns
  `{:error, :missing_account_id}` without an HTTP request
- **Generic HTTP errors** return
  `{:error, %{status: status, response: response_body}}`; responses with a
  `Retry-After` header also include `retry_after: value`. Endpoint-specific
  errors such as `:not_found`, `:unauthorized`, and `:timeout` remain atoms

## Bang Functions

Zone listing has opt-in raising variants:

```elixir
zones = ReqDnsimple.list_zones!(client, per_page: 100)
zones = ReqDnsimple.Zone.list!(client, name_like: "example", per_page: 100)
```

Both return a list directly and fetch only one page, matching their non-bang
counterparts. Existing tuple-returning functions are unchanged.

For other functions returning `{:ok, value}`, `:ok`, or `{:error, reason}`,
use the shared `ReqDnsimple.unwrap!/1` helper:

```elixir
{records, pagination} =
  ReqDnsimple.ZoneRecord.list_page(client, "example.com")
  |> ReqDnsimple.unwrap!()
```

Existing validation and transport exceptions are raised unchanged. Other API
errors raise `ReqDnsimple.Error`, with the original error in `exception.reason`,
including any HTTP status, response body, and retry information.

Only zone listing currently has named bang counterparts; other endpoint `!`
functions are not defined. `unwrap!/1` preserves the inner success value,
including pagination tuples, and leaves `:ok` unchanged. It rejects unsupported
shapes, including the bare lists from `Account.list/1` and `ns_records/2,3` and the
tagged identity tuples from `whoami/1`.

## Sorting and Filtering

List operations accept keyword options validated by NimbleOptions:

```elixir
# Sort ascending by name
ReqDnsimple.Zone.list(client, sort: [name: :asc])

# Sort descending, multiple fields
ReqDnsimple.ZoneRecord.list(client, "example.com",
  sort: [type: :asc, name: :desc]
)

# Filter by name pattern
ReqDnsimple.ZoneRecord.list(client, "example.com",
  name_like: "www",
  type: "A"
)

# Pagination
ReqDnsimple.Zone.list(client, page: 2, per_page: 50)
```

## Token Types

DNSimple uses prefixed tokens. `ReqDnsimple.token_type/1` inspects those prefixes
as a standalone utility; `whoami/1` determines identity from the API response:

```elixir
ReqDnsimple.token_type("dnsimple_u_abc")  # => :user_token
ReqDnsimple.token_type("dnsimple_a_abc")  # => :account_token
ReqDnsimple.token_type("other")           # => :unknown_token
```

Classification is guidance only, not identity discovery or authorization.
Passing a client with dynamic credentials to `token_type/1` evaluates its
callback, so do not use it during construction, re-scoping, or sample setup.
Use explicit `whoami/1` or `Account.list/1` discovery as described above.

## DNSimple API Reference

This library wraps the [DNSimple API v2](https://developer.dnsimple.com/v2/).

## License

MIT
