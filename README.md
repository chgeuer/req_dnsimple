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

### Enable and disable vanity name servers

```elixir
{:ok, vanity_name_servers} =
  ReqDnsimple.VanityNameServer.enable(client, account_id, "example.com")
```

Enabling sends one bodyless request and returns the typed vanity A and AAAA
records created by DNSimple. The API can reject the request when the account's
plan or payment state does not permit vanity name servers.

```elixir
:ok = ReqDnsimple.VanityNameServer.disable(client, account_id, "example.com")
```

Disabling sends one bodyless request to remove the domain's vanity A and AAAA
configuration. Neither operation changes registrar delegation, and disabling
does not delete records individually.

### Retrieve or deregister a webhook endpoint

```elixir
{:ok, webhook} = ReqDnsimple.Webhook.get(client, account_id, webhook_id)
# => {:ok, %ReqDnsimple.Webhook{url: "https://receiver.example/events", suppressed_at: nil}}
```

Webhook retrieval returns the registered callback URL and its nullable
suppression timestamp without contacting the callback URL.

```elixir
:ok = ReqDnsimple.Webhook.delete(client, account_id, webhook_id)
```

Both operations send one bodyless request and accept an integer or
numeric-string webhook ID. Neither operation contacts the callback URL,
inspects deliveries, or lists registrations first.

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

### Order and retrieve certificates

```elixir
{:ok, %ReqDnsimple.Certificate.Purchase{} = purchase} =
  ReqDnsimple.Certificate.purchase_letsencrypt(
    client,
    account_id,
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
    account_id,
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
    account_id,
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
    account_id,
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
    account_id,
    "example.com",
    sort: [expiration: :asc, common_name: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_certificates} =
  ReqDnsimple.Certificate.list_all(
    client,
    account_id,
    "example.com",
    sort: [id: :desc],
    per_page: 100
  )
```

Certificate listing preserves the server's descending-ID order when sorting is
omitted. `list_page/4` (and its `list/4` alias) returns one page with pagination;
`list_all/4` explicitly enumerates from page one.

```elixir
{:ok, %ReqDnsimple.Certificate{} = certificate} =
  ReqDnsimple.Certificate.get(client, account_id, "example.com", certificate_id)
```

Certificate metadata includes its issuance state, alternate names, renewal
setting, and typed creation/update and nullable expiry values.

```elixir
{:ok, %ReqDnsimple.Certificate.Download{} = bundle} =
  ReqDnsimple.Certificate.download(client, account_id, "example.com", certificate_id)
```

The bundle contains the server certificate, nullable root certificate, and
ordered intermediate certificate chain as PEM strings. The strings are
preserved exactly and are not parsed or written to files.

```elixir
{:ok, %ReqDnsimple.Certificate.PrivateKey{private_key: private_key}} =
  ReqDnsimple.Certificate.get_private_key(client, account_id, "example.com", certificate_id)
```

The private key PEM is likewise preserved byte-for-byte and is not parsed,
logged, persisted, or written to a file.

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

### DNS templates

```elixir
{:ok, {templates, pagination}} =
  ReqDnsimple.Template.list_page(client, account_id,
    sort: [id: :asc, name: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_templates} =
  ReqDnsimple.Template.list_all(client, account_id, sort: [sid: :asc])
```

`list_page/3` and its `list/3` alias fetch one page with string-keyed
pagination metadata. `list_all/3` explicitly enumerates from page one while
retaining sorting and `per_page`.

### Domains

```elixir
{:ok, hosted_domain} =
  ReqDnsimple.Domain.create(client, account_id, name: "example.test")

{:ok, domain} = ReqDnsimple.Domain.get(client, account_id, "example.com")

{:ok, {domains, pagination}} =
  ReqDnsimple.Domain.list_page(client, account_id,
    name_like: "example",
    sort: [name: :asc],
    per_page: 30
  )

{:ok, all_domains} =
  ReqDnsimple.Domain.list_all(client, account_id, registrant_id: 42)
```

Domain creation adds the named domain and its hosted zone in one request and
returns a typed `ReqDnsimple.Domain` struct. DNSimple may charge for the DNS
service subscription. It does not register or purchase the domain, change
delegation, verify ownership, or issue a separate zone-creation request.
Retrieval accepts a name or integer ID and returns registration state, privacy,
renewal, and nullable expiry metadata. `list_page/3` and its `list/3` alias
return one typed page with string-keyed pagination metadata; `list_all/3`
explicitly enumerates from page one while retaining `name_like` and
`registrant_id` filters, `id`/`name`/`expiration` sorting, and page size.

### TLD extended attributes

```elixir
{:ok, attributes} = ReqDnsimple.Tld.list_extended_attributes(client, "co.uk")
```

The non-paginated result contains typed
`ReqDnsimple.Tld.ExtendedAttribute` values and their typed options. Registry
attribute names and values remain strings, free-text attributes retain
`options: []`, and an omitted display title is `nil`; a present title is always
a string. This retrieval does not submit registrant data or initiate a
registration or transfer.

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

Retrieve current registration and lifecycle prices without initiating a
purchase:

```elixir
{:ok, %ReqDnsimple.Registrar.Prices{} = prices} =
  ReqDnsimple.Registrar.get_prices(client, account_id, "example.com")
```

Registration, renewal, transfer, restore, and trustee prices remain JSON
numbers. Optional transfer and trustee prices are `nil` when omitted.

Submit a registration for an existing contact without hidden preflight requests:

```elixir
{:ok, %ReqDnsimple.Registrar.Registration{} = registration} =
  ReqDnsimple.Registrar.register(
    client,
    account_id,
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
    account_id,
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
  ReqDnsimple.Registrar.get_transfer_lock(client, account_id, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless request,
and returns both enabled and disabled states in the typed resource without a
domain lookup or mutation.

Explicitly enable the transfer lock without a domain lookup or other registrar
operation:

```elixir
{:ok, %ReqDnsimple.Registrar.TransferLock{enabled: true}} =
  ReqDnsimple.Registrar.enable_transfer_lock(client, account_id, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless POST, and
returns the resulting typed transfer-lock state.

Explicitly disable the transfer lock without requesting an authorization code
or initiating a transfer:

```elixir
{:ok, %ReqDnsimple.Registrar.TransferLock{enabled: false}} =
  ReqDnsimple.Registrar.disable_transfer_lock(client, account_id, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless DELETE,
and returns the resulting typed transfer-lock state.

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

Disable WHOIS privacy without a lookup, refund, or other registrar operation:

```elixir
{:ok, %ReqDnsimple.Registrar.WhoisPrivacy{enabled: false} = privacy} =
  ReqDnsimple.Registrar.disable_whois_privacy(client, account_id, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless DELETE,
and returns the resulting typed privacy state.

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

Retrieve the current registrar delegation without reading hosted-zone records:

```elixir
{:ok, ["ns1.example.com", "ns2.example.com"]} =
  ReqDnsimple.Registrar.get_delegation(client, account_id, "example.com")
```

The operation accepts a domain name or integer ID and returns the ordered
name-server hostnames exactly as DNSimple supplies them.

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

### Registrant changes

```elixir
{:ok, %ReqDnsimple.RegistrantChange{} = change} =
  ReqDnsimple.RegistrantChange.create(
    client,
    account_id,
    domain_id: "example.test",
    contact_id: "11",
    extended_attributes: %{
      "x-fi-registrant-idnumber" => "fake-offline-id"
    }
  )

{:ok, %ReqDnsimple.RegistrantChange{} = change} =
  ReqDnsimple.RegistrantChange.get(client, account_id, registrant_change_id)

{:ok, {changes, pagination}} =
  ReqDnsimple.RegistrantChange.list_page(
    client,
    account_id,
    sort: [id: :asc],
    state: "completed",
    domain_id: "100",
    contact_id: "11",
    page: 2,
    per_page: 30
  )

{:ok, all_pending_changes} =
  ReqDnsimple.RegistrantChange.list_all(client, account_id, state: "pending")

{:ok, %ReqDnsimple.RegistrantChange{state: "cancelling"}} =
  ReqDnsimple.RegistrantChange.cancel(client, account_id, registrant_change_id)
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
{:ok, push} =
  ReqDnsimple.DomainPush.initiate(
    client,
    source_account_id,
    domain,
    new_account_identifier: target_account_identifier
  )

{:ok, {pushes, pagination}} =
  ReqDnsimple.DomainPush.list_page(client, account_id, page: 1, per_page: 30)

{:ok, all_pushes} = ReqDnsimple.DomainPush.list_all(client, account_id)
:ok = ReqDnsimple.DomainPush.accept(client, account_id, push_id, contact_id: contact_id)
:ok = ReqDnsimple.DomainPush.reject(client, account_id, push_id)
```

Initiating a push is source-account scoped and requires exactly one target:
`:new_account_identifier`, or the deprecated `:new_account_email`. Pending-push
listing and acceptance are target-account scoped. `list_page/3` and `list/3`
return one typed page with string-keyed pagination metadata; `list_all/3`
deliberately enumerates from page one and accepts only `:per_page`. Accepting a
push sends exactly one request using the selected target-account contact.
Rejecting a push sends a bodyless request and does not delete the source domain.
None of these operations performs a preflight request.

### DNSSEC

```elixir
{:ok, dnssec} = ReqDnsimple.Dnssec.get(client, account_id, "example.com")
{:ok, dnssec} = ReqDnsimple.Dnssec.enable(client, account_id, "example.com")
:ok = ReqDnsimple.Dnssec.disable(client, account_id, "example.com")
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
    account_id,
    "example.com",
    algorithm: "13",
    digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    digest_type: "2",
    keytag: "12345"
  )

{:ok, delegation_signer_record} =
  ReqDnsimple.DelegationSignerRecord.get(
    client,
    account_id,
    "example.com",
    ds_record_id
  )

{:ok, {delegation_signer_records, pagination}} =
  ReqDnsimple.DelegationSignerRecord.list_page(
    client,
    account_id,
    "example.com",
    sort: [id: :asc, created_at: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_delegation_signer_records} =
  ReqDnsimple.DelegationSignerRecord.list_all(
    client,
    account_id,
    "example.com",
    sort: [created_at: :desc]
  )

:ok =
  ReqDnsimple.DelegationSignerRecord.delete(
    client,
    account_id,
    "example.com",
    ds_record_id
  )
```

Creation accepts a string algorithm with either a complete DS tuple or KEY
`public_key`, and returns a typed `ReqDnsimple.DelegationSignerRecord`. DS and
KEY proof fields that do not apply to the returned representation are `nil`.
`list_page/4` and its `list/4` alias return one typed page with string-keyed
pagination metadata; `list_all/4` explicitly enumerates from page one while
retaining `id`/`created_at` sorting and page size. Deletion removes only the
selected registry delegation-signer record. It does not disable DNSSEC or
delete hosted-zone records.

### Email forwards

```elixir
{:ok, email_forward} =
  ReqDnsimple.EmailForward.create(
    client,
    account_id,
    "example.com",
    alias_name: "support",
    destination_email: "recipient@example.test"
  )

{:ok, email_forward} =
  ReqDnsimple.EmailForward.get(client, account_id, "example.com", email_forward_id)

{:ok, {email_forwards, pagination}} =
  ReqDnsimple.EmailForward.list_page(
    client,
    account_id,
    "example.com",
    sort: [id: :asc, alias_email: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_email_forwards} =
  ReqDnsimple.EmailForward.list_all(
    client,
    account_id,
    "example.com",
    sort: [destination_email: :asc]
  )

:ok = ReqDnsimple.EmailForward.delete(client, account_id, "example.com", email_forward_id)
```

Creation sends the local-part `alias_name` unchanged and returns a typed
`ReqDnsimple.EmailForward` with its full alias email, destination email,
activation state, and timestamps. The returned `alias_email` is distinct from
the creation input. `list_page/4` and its `list/4` alias return one typed page
with string-keyed pagination metadata; `list_all/4` explicitly enumerates from
page one while retaining `id`/`alias_email`/`destination_email` sorting and page
size. Creation does not provision DNS records or send a test email. Deletion
removes only the selected email forward and does not modify the domain's MX
records.

### Secondary-DNS primary servers

```elixir
{:ok, primary_server} =
  ReqDnsimple.PrimaryServer.create(
    client,
    account_id,
    name: "Primary",
    ip: "192.0.2.1",
    port: 5353
  )

{:ok, primary_server} = ReqDnsimple.PrimaryServer.get(client, account_id, primary_server_id)

{:ok, {primary_servers, pagination}} =
  ReqDnsimple.PrimaryServer.list_page(
    client,
    account_id,
    sort: [id: :asc, name: :desc],
    page: 2,
    per_page: 30
  )

{:ok, all_primary_servers} =
  ReqDnsimple.PrimaryServer.list_all(client, account_id, sort: [name: :asc])

{:ok, primary_server} =
  ReqDnsimple.PrimaryServer.link(
    client,
    account_id,
    primary_server_id,
    zone: "secondary.example.test"
  )

{:ok, primary_server} =
  ReqDnsimple.PrimaryServer.unlink(
    client,
    account_id,
    primary_server_id,
    zone: "secondary.example.test"
  )

:ok = ReqDnsimple.PrimaryServer.delete(client, account_id, primary_server_id)
```

The returned `ReqDnsimple.PrimaryServer` includes its IP, integer port, and the
ordered list of linked secondary-zone names. Creation requires a name and IP,
sends a supplied integer port unchanged, and leaves an omitted port to the API.
It performs no reachability check or follow-up request. Retrieval makes no
zone-transfer or reachability requests. `list_page/3` and its `list/3` alias
return one typed page with string-keyed pagination metadata; `list_all/3`
explicitly enumerates from page one while retaining sorting and page size.
Listing supports ordered `id` and `name` sorting. Linking sends the required
secondary-zone name in one request without looking up or creating either
resource. Unlinking removes only that zone association while retaining both
resources and returns the updated primary server. Deletion removes only the
selected primary-server configuration; it does not unlink zones or perform DNS
requests.

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
    account_id,
    "example.com",
    page: 2,
    per_page: 30
  )

{:ok, all_services} =
  ReqDnsimple.Service.list_all_applied(client, account_id, "example.com", per_page: 100)

:ok = ReqDnsimple.Service.apply(client, account_id, "example.com", "service-sid")

:ok =
  ReqDnsimple.Service.apply(
    client,
    account_id,
    "example.com",
    "service-sid",
    settings: %{"app" => "my-app"}
  )

:ok = ReqDnsimple.Service.unapply(client, account_id, "example.com", "service-sid")
```

Service retrieval accepts a sid or integer ID and returns a typed
`ReqDnsimple.Service` with typed nested setting definitions and timestamps.
`list_page/2` and its `list/2` alias return one typed page of the global
catalog, accepting ordered `id`/`sid` sorting and pagination options.
`list_all/2` explicitly enumerates the catalog from page one while preserving
sorting and `per_page`, and rejects an explicit `page`.
`list_page_applied/4` and its `list_applied/4` alias return one typed page of
services applied to a domain with string-keyed pagination metadata.
`list_all_applied/4` explicitly enumerates from page one, preserves `per_page`,
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
| `ReqDnsimple.OAuth` | `/oauth/access_token` | `exchange_code/2` |
| `ReqDnsimple.Account` | `/accounts` | `list/1` |
| `ReqDnsimple.Zone` | `/zones` | `list/3`, `update_ns_records/4`, `get_zone_file/3`, `check_zone_distribution/3` |
| `ReqDnsimple.ZoneRecord` | `/zones/:zone/records`, `/zones/:zone/batch` | `list/4`, `get/4`, `create/4`, `update/5`, `delete/4`, `check_distribution/4`, `batch_change/4` |
| `ReqDnsimple.BillingCharge` | `/billing/charges` | `list/3` |
| `ReqDnsimple.Contact` | `/contacts` | `list/3`, `get/3`, `delete/3` |
| `ReqDnsimple.Domain` | `/domains`, `/domains/:domain` | `create/3`, `get/3`, `list/3`, `list_page/3`, `list_all/3`, `delete/3` |
| `ReqDnsimple.DomainResearch` | `/domains/research/status` | `get_status/3` |
| `ReqDnsimple.DelegationSignerRecord` | `/domains/:domain/ds_records[/:ds_record]` | `create/4`, `get/4`, `list/4`, `list_page/4`, `list_all/4`, `delete/4` |
| `ReqDnsimple.EmailForward` | `/domains/:domain/email_forwards[/:email_forward]` | `create/4`, `get/4`, `delete/4` |
| `ReqDnsimple.DomainPush` | `/domains/:domain/pushes`, `/pushes[/:push]` | `initiate/4`, `list/3`, `list_page/3`, `list_all/3`, `accept/4`, `reject/3` |
| `ReqDnsimple.VanityNameServer` | `/vanity/:domain` | `enable/3`, `disable/3` |
| `ReqDnsimple.Registrar` | `/registrar/domains/:domain` | `check/3`, `get_prices/3`, `get_transfer_lock/3`, `enable_transfer_lock/3`, `disable_transfer_lock/3`, `authorize_transfer_out/3`, `disable_auto_renewal/3`, `enable_auto_renewal/3`, `enable_whois_privacy/3`, `disable_whois_privacy/3`, `register/4`, `transfer/4`, `renew/3`, `renew/4`, `restore/3`, `restore/4`, `get_delegation/3`, `change_delegation/4` |
| `ReqDnsimple.Tld` | `/tlds/:tld`, `/tlds/:tld/extended_attributes` | `get/2`, `list_extended_attributes/2` |
| `ReqDnsimple.PrimaryServer` | `/secondary_dns/primaries` | `create/3`, `get/3`, `list/3`, `list_page/3`, `list_all/3`, `link/4`, `unlink/4`, `delete/3`, `from_json/1` |
| `ReqDnsimple.Service` | `/services[/:service]`, `/domains/:domain/services[/:service]` | `get/2`, `list/1`, `list/2`, `list_page/1`, `list_page/2`, `list_all/1`, `list_all/2`, `list_applied/3`, `list_applied/4`, `list_page_applied/3`, `list_page_applied/4`, `list_all_applied/3`, `list_all_applied/4`, `apply/4`, `apply/5`, `unapply/4` |
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
