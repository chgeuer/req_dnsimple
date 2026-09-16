# ReqDnsimple

[![Hex version badge](https://img.shields.io/hexpm/v/req_dnsimple.svg)](https://hex.pm/packages/req_dnsimple)

A lightweight [DNSimple](https://dnsimple.com) API v2 client for Elixir, built on [Req](https://hexdocs.pm/req).

No framework dependencies — just Req, NimbleOptions, and straightforward Elixir structs.

ReqDnsimple intentionally exposes a documented subset of the published DNSimple
API rather than claiming complete endpoint coverage. The versioned
[operation inventory](docs/audit/operation-inventory.json) is the source of truth
for that boundary:

- `existing` marks operations available before the API-parity campaign.
- `implemented` marks operations added and contract-tested since that baseline.
- `pending` marks approved operations that are not implemented yet.
- `out-of-scope` marks published DNSimple operations deliberately excluded from
  the supported boundary.

The inventory records implementation and test evidence; the repository's `br`
tracker remains the authority for live campaign progress.
It currently reconciles 110 supported operations (13 original, 90 campaign
additions, and seven official Elixir SDK-parity additions) with executable
contract-test locations. One additional published operation, `getDomainRestore`,
remains explicitly `out-of-scope`. The supported endpoints include all 99
operations in the reference DNSimple Elixir SDK v10.0.0, plus 11 additional
operations. OAuth URL generation is a local helper, not another API endpoint.

Account-scoped overloads do not add DNSimple endpoints. The inventory's
`scoped_interfaces` covers 102 account-path operations and 144 interface families,
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

Every HTTP operation returns `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
`{:error, %ReqDnsimple.Error{}}`, in scoped and explicit-account forms alike.
Examples use `_metadata` when they deliberately ignore it. See
[return value conventions](#return-value-conventions) for response headers,
nested pagination, and per-page metadata from complete enumeration. This is a
breaking result-contract change, not a compatibility mode.

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

Client query `params` may be maps or tuple lists. Query operations retain
inherited parameters and override matching names with their explicit options,
including atom/string spellings of the same key. Complete enumeration overrides
an inherited page number so it still starts at page one. Prefer operation
options when available so endpoint-specific validation applies.

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
{:ok, {zones, _metadata}} = ReqDnsimple.Zone.list(client, name_like: "example")
{:ok, {zone, _metadata}} = ReqDnsimple.Zone.get(client, "example.com")

other_account_id = System.fetch_env!("DNSIMPLE_OTHER_ACCOUNT_ID")
other_client = ReqDnsimple.for_account(client, other_account_id)

# An explicit account overrides scope for this call only.
{:ok, {other_zones, _metadata}} = ReqDnsimple.Zone.list(client, other_account_id, per_page: 20)
{:ok, {original_zones, _metadata}} = ReqDnsimple.Zone.list(client, per_page: 20)
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

{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}} =
  ReqDnsimple.Zone.list(discovery)
```

A new account-free operation on an unscoped client returns
`{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
locally, without HTTP or credential resolution. Bang forms raise the same
structured error. Invalid HTTP-operation attributes or options return
`ReqDnsimple.Error` with a `NimbleOptions.ValidationError` in `reason` and
`metadata: nil`; constructor configuration still raises `ArgumentError`.

**Compatibility:** `new_client/1` retains its exact legacy unscoped behavior,
including accepting account tokens. Existing explicit-account calls remain
supported on either kind of client:

```elixir
legacy = ReqDnsimple.new_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:ok, {zones, _metadata}} = ReqDnsimple.Zone.list(legacy, account_id)
```

Global `whoami/1`, `Account.list/1`, `OAuth.exchange_code/2`, TLD catalogs, and
the global Service catalog do not require scope and also work on scoped clients.
Scoping does not change the uniform HTTP result contract.

### Build an OAuth authorization URL

URL generation is local: it does not open a browser, send HTTP, resolve bearer
callbacks, or inherit the client's selected account. No access token is needed:

```elixir
transport = ReqDnsimple.new_unscoped_client("")
state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

{:ok, authorization_url} =
  ReqDnsimple.OAuth.authorize_url(transport, "your-client-id",
    state: state,
    redirect_uri: "http://127.0.0.1:54321/callback",
    code_challenge: challenge,
    code_challenge_method: "S256"
  )
```

The production API origin maps to `https://app.dnsimple.com/oauth/authorize`;
sandbox maps to `https://sandbox.dnsimple.com/oauth/authorize`. Static string
and `URI` HTTP(S) base URLs are supported. Other origins retain their scheme
and port with a leading `api.` removed; API paths, queries, and fragments are
not copied into the authorization URL.

Retain `state` and `verifier` in your application session. Always supply an
unguessable state and validate the callback's state before exchanging its code.
The helper does not manage an OAuth session or callback server. PKCE requires
both a 43-character base64url challenge and `code_challenge_method: "S256"`;
the verifier must never appear in the browser URL.

Optional `account_id:` selects a preferred account on the authorization page
only when explicitly supplied. `state` and `redirect_uri` are forwarded
unchanged, including explicit empty strings; empty state values are not
suitable for an actual authorization flow. Unknown or duplicate options and
malformed origins return validation errors.

### Exchange an OAuth authorization code

Use the same client as a transport configuration; token exchange strips its
inherited Authorization header and does not evaluate a dynamic bearer callback.
Public clients provide the retained PKCE verifier and the same redirect URI
and state used when constructing the authorization URL:

```elixir
{:ok, {token, _metadata}} =
  ReqDnsimple.OAuth.exchange_code(transport,
    client_id: "your-client-id",
    code: "authorization-code",
    grant_type: "authorization_code",
    code_verifier: verifier,
    redirect_uri: "http://127.0.0.1:54321/callback",
    state: state
  )
```

Confidential clients provide `:client_secret` instead of `:code_verifier`.
The result is `{:ok, {%ReqDnsimple.OAuth.Token{}, metadata}}`; `scope` may be
`nil`. Unlike this HTTP exchange, the pure `authorize_url/2,3` helper still
returns `{:ok, url}` or `{:error, %NimbleOptions.ValidationError{}}` without
response metadata.

### Identify yourself

```elixir
{:ok, {identity, metadata}} = ReqDnsimple.whoami(client)
# identity is {:user, user} or {:account, account}.
# metadata is a %ReqDnsimple.Metadata{} for this response.
```

`whoami/1` selects `{:user, user}` or `{:account, account}` from the non-null
identity in the successful response, independently of token spelling or the
client's authentication configuration. If both identities are present or both
are absent, `data` is `{:unknown_token, full_response_body}`. The tagged
identity is always inside `{:ok, {data, metadata}}`, including the unknown case;
the response body is identity data, not a metadata field.

### Discover an account explicitly

An account token can identify its account with an explicit `whoami/1` request:

```elixir
discovery = ReqDnsimple.new_unscoped_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:ok, {{:account, %{"id" => discovered_id}}, _metadata}} = ReqDnsimple.whoami(discovery)
client = ReqDnsimple.for_account(discovery, discovered_id)
```

For a user token, list accessible accounts, then select an account deliberately:

```elixir
discovery = ReqDnsimple.new_unscoped_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:ok, {accounts, _metadata}} = ReqDnsimple.Account.list(discovery)
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
{:ok, {zones, _metadata}} = ReqDnsimple.Zone.list(client)
# => {:ok, {[%ReqDnsimple.Zone{name: "example.com", ...}, ...], %ReqDnsimple.Metadata{...}}}
```

Filter and sort:

```elixir
{:ok, {zones, _metadata}} = ReqDnsimple.Zone.list(client,
  name_like: "example",
  sort: [:id, name: :asc]
)
```

`list` and `list_page` both expose metadata for one response. Use the explicit
scoped `list_page/1,2` name for page-oriented code, or `list_all/1,2` to fetch
every page from page one:

```elixir
{:ok, {zones, metadata}} = ReqDnsimple.Zone.list_page(client, per_page: 50)
pagination = metadata.pagination

{:ok, {all_zones, all_metadata}} = ReqDnsimple.Zone.list_all(client, name_like: "example")
page_metadata = all_metadata.pages
```

`Contact` and `BillingCharge` provide the same scoped `list_page/1,2` and
`list_all/1,2` interfaces. `ZoneRecord` provides `list_page/2,3` and
`list_all/2,3`, with the zone argument retained. Explicit-account forms remain
available, as listed in the API catalog below. `list_all`
preserves filters, sorting, and `per_page`, but rejects `page` because complete
enumeration always begins at page one.

### Get a zone

```elixir
{:ok, {zone, _metadata}} = ReqDnsimple.Zone.get(client, "example.com")
# => {:ok, {%ReqDnsimple.Zone{name: "example.com", active: true, ...}, %ReqDnsimple.Metadata{...}}}
```

This sends one bodyless request and returns the complete zone, including its
reverse, secondary, activation, and nullable last-transfer fields.

### Query DNS analytics

DNS analytics retain the endpoint's tabular headers, rows, and echoed query
metadata:

```elixir
{:ok, {result, metadata}} =
  ReqDnsimple.DnsAnalytics.list_page(client,
    start_date: "2026-09-01",
    end_date: "2026-09-02",
    groupings: [:date, :zone_name],
    sort: [date: :asc, volume: :desc],
    page: 1,
    per_page: 1000
  )

pagination = metadata.pagination
```

Scoped `query/2` is a single-page alias. `list_all/2` explicitly enumerates from page
one and returns one `%ReqDnsimple.DnsAnalytics.Result{}` with compatible rows
combined in server order and the first page's query retained as provenance,
paired with aggregate response metadata in `{:ok, {result, metadata}}`.

### Activate DNS service for a zone

The mutation snippets below illustrate individual APIs; they can change live
DNS or incur charges. For an executable, guarded mutation example, use the
[opt-in sandbox record lifecycle](samples/README.md#opt-in-mutation-one-record-lifecycle).

```elixir
{:ok, {zone, _metadata}} = ReqDnsimple.Zone.activate(client, "example.com")
# => {:ok, {%ReqDnsimple.Zone{active: true, ...}, %ReqDnsimple.Metadata{...}}}
```

Activation sends one bodyless request and returns the resulting zone. DNSimple
may renew an expired domain subscription and charge the account during
activation. The client does not preflight billing, register a domain, or make
follow-up requests.

### Deactivate DNS service for a zone

```elixir
{:ok, {zone, _metadata}} = ReqDnsimple.Zone.deactivate(client, "example.com")
# => {:ok, {%ReqDnsimple.Zone{active: false, ...}, %ReqDnsimple.Metadata{...}}}
```

Deactivation sends one bodyless request and stops DNS resolution without
deleting the zone, domain, or records. The client performs no preflight,
follow-up request, or additional mutation.

### Manage DNS records

**List records for a zone:**

```elixir
{:ok, {records, metadata}} = ReqDnsimple.ZoneRecord.list(
  client, "example.com",
  type: "A",
  sort: [:id, name: :asc]
)
pagination = metadata.pagination
```

**Create a record:**

```elixir
{:ok, {record, _metadata}} = ReqDnsimple.ZoneRecord.create(
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
{:ok, {record, _metadata}} = ReqDnsimple.ZoneRecord.update(
  client, "example.com", record_id,
  content: "93.184.215.15", ttl: 1800
)
```

For standalone create and update, `ttl` and `priority` accept non-negative
integers; `priority` also accepts `nil`, sent unchanged as JSON `null`.
Explicit zero values are sent unchanged; omitted fields remain absent from
the request. Batch record priorities remain non-negative integers only.
For create and update, `integrated_zones` accepts integer zone IDs and the
literal `"dnsimple"` target, for example `[1, 2, "dnsimple"]`. Omitting the
option lets the API propagate the mutation to its default targets; an explicit
list, including an empty list, is sent unchanged. The endpoint documentation
and examples support `"dnsimple"` even though the OpenAPI item schema currently
declares integers only.

**Apply an atomic batch:**

```elixir
{:ok, {%ReqDnsimple.ZoneRecord.BatchResult{} = result, _metadata}} =
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
{:ok, {nil, _metadata}} = ReqDnsimple.ZoneRecord.delete(client, "example.com", record_id)
```

### Update hosted-zone NS records

```elixir
{:ok, {ns_records, _metadata}} =
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
{:ok, {vanity_name_servers, _metadata}} =
  ReqDnsimple.VanityNameServer.enable(client, "example.com")
```

Enabling sends one bodyless request and returns the typed vanity A and AAAA
records created by DNSimple. The API can reject the request when the account's
plan or payment state does not permit vanity name servers.

```elixir
{:ok, {nil, _metadata}} = ReqDnsimple.VanityNameServer.disable(client, "example.com")
```

Disabling sends one bodyless request to remove the domain's vanity A and AAAA
configuration. Neither operation changes registrar delegation, and disabling
does not delete records individually.

### List, register, retrieve, or deregister webhook endpoints

```elixir
{:ok, {webhooks, _metadata}} =
  ReqDnsimple.Webhook.list(client, sort: [id: :asc])
```

Webhook listing returns the complete, non-paginated collection and supports
ordered `id` sorting.

```elixir
{:ok, {webhook, _metadata}} =
  ReqDnsimple.Webhook.create(
    client,
    url: "https://receiver.example/events?source=dnsimple"
  )
```

Webhook registration requires an absolute HTTPS callback URL and sends it
unchanged in one POST request without contacting or probing the callback.

```elixir
{:ok, {webhook, _metadata}} = ReqDnsimple.Webhook.get(client, webhook_id)
# => {:ok, {%ReqDnsimple.Webhook{url: "https://receiver.example/events", suppressed_at: nil}, %ReqDnsimple.Metadata{...}}}
```

Webhook retrieval returns the registered callback URL and its nullable
suppression timestamp without contacting the callback URL.

```elixir
{:ok, {nil, _metadata}} = ReqDnsimple.Webhook.delete(client, webhook_id)
```

Listing, retrieval, and deletion send one bodyless request. Retrieval and
deletion accept an integer or numeric-string webhook ID. None of these
operations contacts the callback URL or inspects deliveries.

### Get a zone file

```elixir
{:ok, {zone_file, _metadata}} = ReqDnsimple.Zone.get_zone_file(client, "example.com")
# => {:ok, {"$ORIGIN example.com.\n$TTL 3600\n...", %ReqDnsimple.Metadata{...}}}
```

### Check zone distribution

```elixir
{:ok, {true, _metadata}} = ReqDnsimple.Zone.check_zone_distribution(client, "example.com")
```

### Check zone record distribution

```elixir
{:ok, {false, _metadata}} =
  ReqDnsimple.ZoneRecord.check_distribution(client, "example.com", record_id)
```

### Order and retrieve certificates

```elixir
{:ok, {%ReqDnsimple.Certificate.Purchase{} = purchase, _metadata}} =
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
{:ok, {%ReqDnsimple.Certificate.Renewal{} = renewal, _metadata}} =
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
{:ok, {%ReqDnsimple.Certificate{state: "requesting"} = certificate, _metadata}} =
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
{:ok, {%ReqDnsimple.Certificate{state: "requesting"} = replacement, _metadata}} =
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
{:ok, {certificates, metadata}} =
  ReqDnsimple.Certificate.list_page(
    client,
    "example.com",
    sort: [expiration: :asc, common_name: :desc],
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_certificates, _metadata}} =
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
{:ok, {%ReqDnsimple.Certificate{} = certificate, _metadata}} =
  ReqDnsimple.Certificate.get(client, "example.com", certificate_id)
```

Certificate metadata includes its issuance state, alternate names, renewal
setting, and typed creation/update and nullable expiry values.

```elixir
{:ok, {%ReqDnsimple.Certificate.Download{} = bundle, _metadata}} =
  ReqDnsimple.Certificate.download(client, "example.com", certificate_id)
```

The bundle contains the server certificate, nullable root certificate, and
ordered intermediate certificate chain as PEM strings. The strings are
preserved exactly and are not parsed or written to files.

```elixir
{:ok, {%ReqDnsimple.Certificate.PrivateKey{private_key: private_key}, _metadata}} =
  ReqDnsimple.Certificate.get_private_key(client, "example.com", certificate_id)
```

The private key PEM is likewise preserved byte-for-byte and is not parsed,
logged, persisted, or written to a file.

### Billing charges

```elixir
{:ok, {charges, _metadata}} = ReqDnsimple.BillingCharge.list(client,
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
{:ok, {contact, _metadata}} =
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

{:ok, {contact, _metadata}} =
  ReqDnsimple.Contact.update(client, contact_id,
    label: "",
    address2: nil,
    fax: nil
  )

{:ok, {contacts, _metadata}} = ReqDnsimple.Contact.list(client, sort: [label: :asc])
{:ok, {contact, _metadata}}  = ReqDnsimple.Contact.get(client, contact_id)
{:ok, {nil, _metadata}} = ReqDnsimple.Contact.delete(client, contact_id)
```

### DNS templates

```elixir
{:ok, {templates, metadata}} =
  ReqDnsimple.Template.list_page(client,
    sort: [id: :asc, name: :desc],
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_templates, _metadata}} =
  ReqDnsimple.Template.list_all(client, sort: [sid: :asc])

{:ok, {template, _metadata}} =
  ReqDnsimple.Template.update(client, "offline-template",
    description: ""
  )
```

Scoped `list_page/2` and its `list/2` alias fetch one page with string-keyed
pagination metadata. `list_all/2` explicitly enumerates from page one while
retaining sorting and `per_page`. `update/3` patches only the supplied metadata
and uses the caller's original template identifier for the request path.

`TemplateRecord.create/3,4` accepts known record types case-insensitively,
including lowercase values such as `type: "mx"`. Unknown record types remain
validation errors.

### Domains

```elixir
{:ok, {hosted_domain, _metadata}} =
  ReqDnsimple.Domain.create(client, name: "example.test")

{:ok, {domain, _metadata}} = ReqDnsimple.Domain.get(client, "example.com")

{:ok, {domains, metadata}} =
  ReqDnsimple.Domain.list_page(client,
    name_like: "example",
    sort: [name: :asc],
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_domains, _metadata}} =
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
Older domain payloads may omit `expires_at`; it remains `nil`, while
`expires_on` is preserved independently rather than converted into an invented
expiry timestamp.

### TLD capabilities and extended attributes

```elixir
{:ok, {tlds, metadata}} =
  ReqDnsimple.Tld.list_page(client, sort: [tld: :asc], per_page: 30)
pagination = metadata.pagination

{:ok, {all_tlds, _metadata}} = ReqDnsimple.Tld.list_all(client, sort: [tld: :asc])

{:ok, {attributes, _metadata}} = ReqDnsimple.Tld.list_extended_attributes(client, "co.uk")
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
{:ok, {%ReqDnsimple.Registrar.CheckResult{} = result, _metadata}} =
  ReqDnsimple.Registrar.check(client, "example.com")
```

The registrar check is intended for low-volume interactive use and has a
stricter rate limit than most DNSimple endpoints. It reports availability,
premium status, and the optional trustee flag without using the paid Domain
Research API, registering the domain, or retrying a rate-limited request.

Retrieve current registration and lifecycle prices without initiating a
purchase:

```elixir
{:ok, {%ReqDnsimple.Registrar.Prices{} = prices, _metadata}} =
  ReqDnsimple.Registrar.get_prices(client, "example.com")
```

Registration, renewal, transfer, restore, and trustee prices remain JSON
numbers. Optional transfer and trustee prices are `nil` when omitted.

Submit a registration for an existing contact without hidden preflight requests:

```elixir
{:ok, {%ReqDnsimple.Registrar.Registration{} = registration, _metadata}} =
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
{:ok, {%ReqDnsimple.Registrar.Transfer{} = transfer, _metadata}} =
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
{:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: enabled}, _metadata}} =
  ReqDnsimple.Registrar.get_transfer_lock(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless request,
and returns both enabled and disabled states in the typed resource without a
domain lookup or mutation.

Explicitly enable the transfer lock without a domain lookup or other registrar
operation:

```elixir
{:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: true}, _metadata}} =
  ReqDnsimple.Registrar.enable_transfer_lock(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless POST, and
returns the resulting typed transfer-lock state.

Explicitly disable the transfer lock without requesting an authorization code
or initiating a transfer:

```elixir
{:ok, {%ReqDnsimple.Registrar.TransferLock{enabled: false}, _metadata}} =
  ReqDnsimple.Registrar.disable_transfer_lock(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless DELETE,
and returns the resulting typed transfer-lock state.

Enable or disable future automatic renewal without renewing or otherwise
modifying the domain:

```elixir
{:ok, {nil, _metadata}} = ReqDnsimple.Registrar.enable_auto_renewal(client, "example.com")
{:ok, {nil, _metadata}} = ReqDnsimple.Registrar.disable_auto_renewal(client, "example.com")
```

Both operations accept a domain name or integer ID, send one bodyless request,
and return registry or TLD refusal responses as explicit errors.

Enable WHOIS privacy without a price lookup or purchase preflight:

```elixir
{:ok, {%ReqDnsimple.Registrar.WhoisPrivacy{} = privacy, _metadata}} =
  ReqDnsimple.Registrar.enable_whois_privacy(client, "example.com")
```

The operation accepts a domain name or integer ID and returns the typed privacy
state for modern HTTP 200 and legacy HTTP 201 responses. It sends one bodyless
request and does not promise or initiate a separate one-year purchase. Legacy
creation responses may contain null `enabled` and `expires_on` values; both
remain `nil` in the result. Payment failures, including HTTP 402, are returned
as explicit errors.

Disable WHOIS privacy without a lookup, refund, or other registrar operation:

```elixir
{:ok, {%ReqDnsimple.Registrar.WhoisPrivacy{enabled: false} = privacy, _metadata}} =
  ReqDnsimple.Registrar.disable_whois_privacy(client, "example.com")
```

The operation accepts a domain name or integer ID, sends one bodyless DELETE,
and returns the resulting typed privacy state.

Submit a renewal without a price lookup or follow-up polling:

```elixir
{:ok, {%ReqDnsimple.Registrar.Renewal{} = renewal, _metadata}} =
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
{:ok, {%ReqDnsimple.Registrar.Restore{} = restore, _metadata}} =
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

Retrieve individual lifecycle jobs using the IDs returned by their submission
operations, without resubmitting them or automatically polling:

```elixir
{:ok, {registration, _metadata}} =
  ReqDnsimple.Registrar.get_registration(client, "example.com", registration.id)

{:ok, {renewal, _metadata}} =
  ReqDnsimple.Registrar.get_renewal(client, "example.com", renewal.id)

{:ok, {transfer, _metadata}} =
  ReqDnsimple.Registrar.get_transfer(client, "example.com", transfer.id)
```

These IDs identify the registration, renewal, or transfer job, not the domain.
The results use the existing `Registration`, `Renewal`, and `Transfer` structs.
Renewal retrieval also accepts legacy HTTP 201 responses.

Request cancellation of an incoming transfer explicitly:

```elixir
{:ok, {transfer, _metadata}} =
  ReqDnsimple.Registrar.cancel_transfer(client, "example.com", transfer.id)
```

Cancellation returns the typed transfer for an accepted HTTP 202 request.
It does not promise that cancellation has completed, poll, or delete the
domain; registry and eligibility refusals remain explicit errors.

Retrieve the current registrar delegation without reading hosted-zone records:

```elixir
{:ok, {["ns1.example.com", "ns2.example.com"], _metadata}} =
  ReqDnsimple.Registrar.get_delegation(client, "example.com")
```

The operation accepts a domain name or integer ID and returns the ordered
name-server hostnames exactly as DNSimple supplies them.

```elixir
{:ok, {name_servers, _metadata}} =
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

Change registrar delegation to or from vanity name servers:

```elixir
{:ok, {vanity_name_servers, _metadata}} =
  ReqDnsimple.Registrar.change_delegation_to_vanity(client, "example.com",
    name_servers: ["ns1.example.com", "ns2.example.com"]
  )

{:ok, {nil, _metadata}} = ReqDnsimple.Registrar.change_delegation_from_vanity(client, "example.com")
```

The enabling operation sends the supplied names as a root JSON array and
returns ordered `%ReqDnsimple.VanityNameServer{}` records. Changing away from
vanity delegation sends one bodyless request and returns
`{:ok, {nil, metadata}}` for HTTP 204.
These operations change registrar delegation, unlike the record-only
`VanityNameServer.enable/disable` helpers or hosted-zone NS updates.

### Registrant changes

Check registry requirements before deciding whether to submit a contact change:

```elixir
{:ok, {%ReqDnsimple.RegistrantChange.CheckResult{} = requirements, _metadata}} =
  ReqDnsimple.RegistrantChange.check(client,
    domain_id: "example.test",
    contact_id: "11"
  )
```

The result includes resolved domain/contact IDs, `registry_owner_change`, and
the complete registry `extended_attributes` definitions as maps. Checking does
not create a change or modify the registrant. Creation remains a separate,
explicit operation and does not automatically perform this check:

```elixir
{:ok, {%ReqDnsimple.RegistrantChange{} = change, _metadata}} =
  ReqDnsimple.RegistrantChange.create(
    client,
    domain_id: "example.test",
    contact_id: "11",
    extended_attributes: %{
      "x-fi-registrant-idnumber" => "fake-offline-id"
    }
  )

{:ok, {%ReqDnsimple.RegistrantChange{} = change, _metadata}} =
  ReqDnsimple.RegistrantChange.get(client, registrant_change_id)

{:ok, {changes, metadata}} =
  ReqDnsimple.RegistrantChange.list_page(
    client,
    sort: [id: :asc],
    state: "completed",
    domain_id: "100",
    contact_id: "11",
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_pending_changes, _metadata}} =
  ReqDnsimple.RegistrantChange.list_all(client, state: "pending")

{:ok, {%ReqDnsimple.RegistrantChange{state: "cancelling"}, _metadata}} =
  ReqDnsimple.RegistrantChange.cancel(client, registrant_change_id)
```

Registrant-change creation accepts domain/contact integer IDs or string forms,
including a domain name, and returns either an immediately completed or pending
request without polling. Creation preserves omitted versus explicitly empty
registry extended attributes and performs no requirements check. Retrieval
returns the current state, dynamic registry extended attributes with string
keys, and typed date/timestamp fields. A pending registry lock-lift date remains
`nil`. Cancellation returns the typed current request for an asynchronous
cancellation, or `nil` data when cancellation completes immediately. Both use
`{:ok, {data, metadata}}`; neither polls.

### Domain Research

```elixir
{:ok, {research, _metadata}} =
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

{:ok, {push, _metadata}} =
  ReqDnsimple.DomainPush.initiate(
    source_client,
    domain,
    new_account_identifier: target_account_identifier
  )

{:ok, {pushes, metadata}} =
  ReqDnsimple.DomainPush.list_page(target_client, page: 1, per_page: 30)
pagination = metadata.pagination

{:ok, {all_pushes, _metadata}} = ReqDnsimple.DomainPush.list_all(target_client)
{:ok, {nil, _metadata}} = ReqDnsimple.DomainPush.accept(target_client, push_id, contact_id: contact_id)
{:ok, {nil, _metadata}} = ReqDnsimple.DomainPush.reject(target_client, push_id)
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
{:ok, {dnssec, _metadata}} = ReqDnsimple.Dnssec.get(client, "example.com")
{:ok, {dnssec, _metadata}} = ReqDnsimple.Dnssec.enable(client, "example.com")
{:ok, {nil, _metadata}} = ReqDnsimple.Dnssec.disable(client, "example.com")
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
{:ok, {delegation_signer_record, _metadata}} =
  ReqDnsimple.DelegationSignerRecord.create(
    client,
    "example.com",
    algorithm: "13",
    digest: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
    digest_type: "2",
    keytag: "12345"
  )

{:ok, {delegation_signer_record, _metadata}} =
  ReqDnsimple.DelegationSignerRecord.get(
    client,
    "example.com",
    ds_record_id
  )

{:ok, {delegation_signer_records, metadata}} =
  ReqDnsimple.DelegationSignerRecord.list_page(
    client,
    "example.com",
    sort: [id: :asc, created_at: :desc],
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_delegation_signer_records, _metadata}} =
  ReqDnsimple.DelegationSignerRecord.list_all(
    client,
    "example.com",
    sort: [created_at: :desc]
  )

{:ok, {nil, _metadata}} =
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
{:ok, {email_forward, _metadata}} =
  ReqDnsimple.EmailForward.create(
    client,
    "example.com",
    alias_name: "support",
    destination_email: "recipient@example.test"
  )

{:ok, {email_forward, _metadata}} =
  ReqDnsimple.EmailForward.get(client, "example.com", email_forward_id)

{:ok, {email_forwards, metadata}} =
  ReqDnsimple.EmailForward.list_page(
    client,
    "example.com",
    sort: [id: :asc, alias_email: :desc],
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_email_forwards, _metadata}} =
  ReqDnsimple.EmailForward.list_all(
    client,
    "example.com",
    sort: [destination_email: :asc]
  )

{:ok, {nil, _metadata}} = ReqDnsimple.EmailForward.delete(client, "example.com", email_forward_id)
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
{:ok, {primary_server, _metadata}} =
  ReqDnsimple.PrimaryServer.create(
    client,
    name: "Primary",
    ip: "192.0.2.1",
    port: 5353
  )

{:ok, {primary_server, _metadata}} = ReqDnsimple.PrimaryServer.get(client, primary_server_id)

{:ok, {primary_servers, metadata}} =
  ReqDnsimple.PrimaryServer.list_page(
    client,
    sort: [id: :asc, name: :desc],
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_primary_servers, _metadata}} =
  ReqDnsimple.PrimaryServer.list_all(client, sort: [name: :asc])

{:ok, {primary_server, _metadata}} =
  ReqDnsimple.PrimaryServer.link(
    client,
    primary_server_id,
    zone: "secondary.example.test"
  )

{:ok, {primary_server, _metadata}} =
  ReqDnsimple.PrimaryServer.unlink(
    client,
    primary_server_id,
    zone: "secondary.example.test"
  )

{:ok, {nil, _metadata}} = ReqDnsimple.PrimaryServer.delete(client, primary_server_id)
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
{:ok, {zone, _metadata}} =
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
{:ok, {service, _metadata}} = ReqDnsimple.Service.get(client, "service-sid")

{:ok, {catalog, metadata}} =
  ReqDnsimple.Service.list_page(
    client,
    sort: [id: :asc, sid: :desc],
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_catalog_services, _metadata}} =
  ReqDnsimple.Service.list_all(client, sort: [sid: :asc], per_page: 100)

{:ok, {services, metadata}} =
  ReqDnsimple.Service.list_page_applied(
    client,
    "example.com",
    page: 2,
    per_page: 30
  )
pagination = metadata.pagination

{:ok, {all_services, _metadata}} =
  ReqDnsimple.Service.list_all_applied(client, "example.com", per_page: 100)

{:ok, {nil, _metadata}} = ReqDnsimple.Service.apply(client, "example.com", "service-sid")

{:ok, {nil, _metadata}} =
  ReqDnsimple.Service.apply(
    client,
    "example.com",
    "service-sid",
    settings: %{"app" => "my-app"}
  )

{:ok, {nil, _metadata}} = ReqDnsimple.Service.unapply(client, "example.com", "service-sid")
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
from the separate API that explicitly replaces a zone's NS records. The result
is `{:ok, {records, metadata}}`, with aggregate response metadata and every
requested page in `metadata.pages`.

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
| `ReqDnsimple.OAuth` | Local authorization URL; `/oauth/access_token` | `authorize_url/2,3`, `exchange_code/2` |
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
| `ReqDnsimple.Registrar` | `/registrar/domains/:domain` | `check/2,3`, `get_prices/2,3`, `get_transfer_lock/2,3`, `enable_transfer_lock/2,3`, `disable_transfer_lock/2,3`, `authorize_transfer_out/2,3`, `disable_auto_renewal/2,3`, `enable_auto_renewal/2,3`, `enable_whois_privacy/2,3`, `disable_whois_privacy/2,3`, `register/3,4`, `get_registration/3,4`, `transfer/3,4`, `get_transfer/3,4`, `cancel_transfer/3,4`, `renew/2,3,4`, `get_renewal/3,4`, `restore/2,3,4`, `get_delegation/2,3`, `change_delegation/3,4`, `change_delegation_to_vanity/3,4`, `change_delegation_from_vanity/2,3` |
| `ReqDnsimple.RegistrantChange` | `/registrar/registrant_changes[/:registrant_change]` | `check/2,3`, `create/2,3`, `get/2,3`, `list/1,2,3`, `list_page/1,2,3`, `list_all/1,2,3`, `cancel/2,3` |
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

Every HTTP operation uses `ReqDnsimple.Response.result(data)`:

```elixir
{:ok, {data, %ReqDnsimple.Metadata{} = metadata}}
{:error, %ReqDnsimple.Error{reason: reason, metadata: metadata}}
```

`ReqDnsimple.Response` is the shared result formatter and typespec namespace,
**not** a returned struct. `ReqDnsimple.Metadata` is the returned metadata
struct. The data keeps its resource type: typed structs, lists, booleans, zone
file strings, OAuth tokens, or tagged `whoami` identities. HTTP 204 and other
bodyless successes have `nil` data. `Account.list/1` and `ns_records/2,3` use
this same tuple contract; there are no bare-list HTTP successes.

Resource timestamps are normalized to UTC `DateTime` values, including valid
ISO 8601 offsets. Response rate-limit resets instead use integer Unix seconds.

### Single-response metadata

| Field | Meaning |
| --- | --- |
| `status` | HTTP status of this response, including bodyless successes and failures. |
| `pagination` | Nested string-keyed map, such as `"current_page"`, `"per_page"`, `"total_entries"`, and `"total_pages"`. Access it as `metadata.pagination`, not as the metadata struct itself. |
| `rate_limit` | Non-negative integer request-budget limit when supplied. |
| `rate_limit_remaining` | Non-negative integer remaining budget; zero is meaningful. |
| `rate_limit_reset` | Non-negative integer Unix seconds, not milliseconds, a duration, or a `DateTime`. |
| `request_id` | Opaque request ID string. |
| `etag` | Opaque ETag string, preserving quotes and any weak `W/` prefix. |
| `retry_after` | Opaque Retry-After string; it may be a delay or an HTTP-date. It is not automatically parsed or acted upon. |
| `pages` | `[]` for a single response; ordered per-page metadata for complete enumeration. |
| `parse_errors` | Map of malformed metadata fields; defaults to `%{}`. |

Missing optional values are `nil`. Malformed headers or body pagination are
recorded explicitly in `parse_errors` rather than silently coerced or turned
into failed resource data. Check availability before using optional fields.
Metadata does not retain raw headers or response bodies wholesale.

```elixir
{:ok, {records, metadata}} =
  ReqDnsimple.ZoneRecord.list_page(client, "example.com", per_page: 50)

pagination = metadata.pagination
remaining = metadata.rate_limit_remaining
metadata_problems = metadata.parse_errors
```

### Complete enumeration metadata

`list_all` and `ns_records` return `{:ok, {combined_data, aggregate_metadata}}`.
`aggregate_metadata.pages` preserves each response's metadata in request order,
including empty and single-page collections. Top-level `rate_limit`,
`rate_limit_remaining`, `rate_limit_reset`, `retry_after`, and `parse_errors`
reflect the last page. Top-level `status`, `pagination`, `request_id`, and `etag`
are `nil`: no collection-wide response, pagination map, request ID, or ETag is
fabricated. Inspect `.pages` for those individual values.

```elixir
{:ok, {zones, metadata}} = ReqDnsimple.Zone.list_all(client, per_page: 50)
page_pagination = Enum.map(metadata.pages, & &1.pagination)
page_request_ids = Enum.map(metadata.pages, & &1.request_id)
```

If a later HTTP request fails, `Error.metadata` retains the failing response's
fields, and its `.pages` contains completed pages plus the failed page. A
transport failure retains previously received page metadata without inventing
a failed HTTP response. An incomplete enumeration never returns a successful
partial collection. Malformed pagination remains visible in metadata, but
`list_all` must fail explicitly if it cannot establish a safe complete traversal.

Exposing rate limits, ETags, and Retry-After does **not** add automatic rate
limiting, retries, or caching. Request methods, payloads, and configured Req
behavior are unchanged.

### Errors and pure helpers

HTTP-operation failures always return `{:error, %ReqDnsimple.Error{}}`.
`error.reason` retains the original validation, transport, decoding, or API
reason. Generic HTTP errors retain `%{status: status, response: response_body}`
in `reason`; endpoint-specific reasons remain there when applicable. All
available response metadata is in `error.metadata`, including
`error.metadata.retry_after` rather than `error.reason.retry_after`.
Local validation and transport failures have `metadata: nil` when no earlier
enumeration responses exist. Missing account scope and
`NimbleOptions.ValidationError` reasons are wrapped the same way without HTTP.

```elixir
case ReqDnsimple.Zone.get(client, "example.com") do
  {:ok, {zone, metadata}} ->
    {:zone, zone.name, metadata.status}

  {:error, %ReqDnsimple.Error{reason: reason, metadata: metadata}} ->
    {:failed, reason, metadata}
end
```

Pure helpers do not acquire response metadata. In particular,
`OAuth.authorize_url/2,3` still returns `{:ok, url}` or
`{:error, %NimbleOptions.ValidationError{}}`; only `OAuth.exchange_code/2`
performs HTTP. Client constructors and `for_account/2` still return
`Req.Request` clients and raise `ArgumentError` for invalid configuration.

## Bang Functions

Zone listing has opt-in raising variants:

```elixir
{zones, metadata} = ReqDnsimple.list_zones!(client, per_page: 100)
{zones, metadata} = ReqDnsimple.Zone.list!(client, name_like: "example", per_page: 100)
```

Both remove only the outer `:ok`, return `{zones, metadata}`, and fetch just one
page, matching their non-bang counterparts.

Use `ReqDnsimple.unwrap!/1` with any HTTP operation:

```elixir
{records, metadata} =
  ReqDnsimple.ZoneRecord.list_page(client, "example.com")
  |> ReqDnsimple.unwrap!()
```

HTTP-operation failures raise the structured `ReqDnsimple.Error` unchanged,
preserving both `exception.reason` and `exception.metadata`. Successes retain
the full `{data, metadata}` pair, including `{nil, metadata}` for bodyless
responses. This also works for account listing, apex NS enumeration, and tagged
identities. Only zone listing has named bang counterparts; other endpoint `!`
functions are not defined. The generic helper also retains its pure-value
behavior (`{:ok, value}` unwraps to `value`, and `:ok` stays `:ok`); those are not
alternative HTTP result shapes.

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
