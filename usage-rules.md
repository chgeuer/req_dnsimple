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
- `implemented` marks operations added and contract-tested since that baseline.
- `pending` marks approved operations that are not implemented yet.
- `out-of-scope` marks published DNSimple operations deliberately excluded from
  the supported boundary.

The inventory describes the bounded implementation target and its evidence, not
live issue state. The repository's `br` tracker is the authority for campaign
progress. It currently reconciles 110 supported operations (13 original, 90
campaign additions, and seven official Elixir SDK-parity additions) with
executable contract-test locations. One additional published operation,
`getDomainRestore`, remains explicitly `out-of-scope`. This includes all 99
operations in the reference DNSimple Elixir SDK v10.0.0 and 11 additional
operations. An operation absent from the inventory is not implicitly supported;
OAuth URL generation is a local helper, not another API endpoint.

The additive `scoped_interfaces` metadata covers 102 account-path operations and
144 interface families, including pagination helpers, root shortcuts, and the
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

Inherited query `params` may be maps or tuple lists, including string keys.
Query operations retain unrelated parameters and let explicitly supplied
operation options override matching encoded names. Complete enumeration
overrides inherited page numbers to start at page one. Prefer operation
options for endpoint-specific validation; forwarding an arbitrary client
parameter does not establish that DNSimple supports it.

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
{:ok, {zones, _metadata}} = ReqDnsimple.Zone.list(client, name_like: "example")
{:ok, {zone, _metadata}} = ReqDnsimple.Zone.get(client, "example.com")

other_id = System.fetch_env!("DNSIMPLE_OTHER_ACCOUNT_ID")
other_client = ReqDnsimple.for_account(client, other_id)

# An explicit account wins for one call without rebinding either client.
{:ok, {other_zones, _metadata}} = ReqDnsimple.Zone.list(client, other_id, per_page: 20)
{:ok, {original_zones, _metadata}} = ReqDnsimple.Zone.list(client, per_page: 20)

# Legacy construction and explicit-account calls remain supported.
legacy = ReqDnsimple.new_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:ok, {zones, _metadata}} = ReqDnsimple.Zone.list(legacy, account_id)
```

`for_account/2` validates the same positive ID forms and returns an immutable
copy with identical auth, base URL, options, and adapter. The original client
is unchanged; DNSimple remains the authority on permissions.

New account-free calls on unscoped clients return
`{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
locally, without HTTP or callback evaluation. Bang forms raise the same error.
Invalid HTTP-operation attributes/options return a `ReqDnsimple.Error` with the
original `NimbleOptions.ValidationError` in `reason` and `metadata: nil`.
Constructor configuration still raises `ArgumentError`.

Global `whoami/1`, `Account.list/1`, `OAuth.authorize_url/2,3`,
`OAuth.exchange_code/2`, TLD catalogs, and
Service global catalogs need no scope and also work with scoped clients.
Applying or listing services applied to a domain is account-scoped, unlike
listing the global Service catalog.

The root `list_zones`, `list_zones!`, `list_contacts`, and
`list_billing_charges` helpers accept the same options as their resource
modules in both scoped and explicit-account forms.

## Return Value Patterns

Every HTTP operation returns `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
`{:error, %ReqDnsimple.Error{}}`. This is a breaking result-contract change
across reads, mutations, paginated and non-paginated operations; there is no
compatibility mode. Public HTTP types use `ReqDnsimple.Response.result(data)`.
`ReqDnsimple.Response` is a result formatter and typespec namespace, not a
returned struct; the returned struct is `ReqDnsimple.Metadata`.

Arity lists below include scoped and explicit-account forms; omitting the
account argument does not change the result contract. In the table, `metadata`
is a `ReqDnsimple.Metadata` struct. For complete enumeration it is aggregate
metadata, with individual responses under `metadata.pages`. HTTP 204 and other
bodyless successes have `nil` data. Pure `OAuth.authorize_url/2,3` is the
intentional non-HTTP exception.

| Module | Success | Failure |
|--------|---------|---------|
| `OAuth.authorize_url/2,3` | `{:ok, url}` | `{:error, %NimbleOptions.ValidationError{}}` |
| `ReqDnsimple.whoami/1` | `{:ok, {identity, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ReqDnsimple.ns_records/2,3` | `{:ok, {[%NsRecord{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `OAuth.exchange_code/2` | `{:ok, {%OAuth.Token{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Account.list/1` | `{:ok, {[%Account{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.list/1,2,3` | `{:ok, {[%Zone{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ReqDnsimple.list_zones!/1,2,3` and `Zone.list!/1,2,3` | `{[%Zone{}, ...], metadata}` | Raises `ReqDnsimple.Error` |
| `Zone.list_page/1,2,3` | `{:ok, {[%Zone{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.list_all/1,2,3` | `{:ok, {[%Zone{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.get/2,3` | `{:ok, {%Zone{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.activate/2,3` | `{:ok, {%Zone{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.deactivate/2,3` | `{:ok, {%Zone{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.list/2,3,4` | `{:ok, {[%ZoneRecord{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.list_page/2,3,4` | `{:ok, {[%ZoneRecord{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.list_all/2,3,4` | `{:ok, {[%ZoneRecord{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.create/3,4` | `{:ok, {%ZoneRecord{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.update/4,5` | `{:ok, {%ZoneRecord{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.delete/3,4` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.get/3,4` | `{:ok, {%ZoneRecord{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.check_distribution/3,4` | `{:ok, {boolean(), metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `ZoneRecord.batch_change/3,4` | `{:ok, {%ZoneRecord.BatchResult{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Contact.create/2,3` | `{:ok, {%Contact{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Contact.update/3,4` | `{:ok, {%Contact{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Contact.list/1,2,3` | `{:ok, {[%Contact{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Contact.list_page/1,2,3` | `{:ok, {[%Contact{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Contact.list_all/1,2,3` | `{:ok, {[%Contact{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Contact.get/2,3` | `{:ok, {%Contact{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Contact.delete/2,3` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Domain.create/2,3` | `{:ok, {%Domain{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Domain.get/2,3` | `{:ok, {%Domain{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Domain.list_page/1,2,3` | `{:ok, {[%Domain{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Domain.list_all/1,2,3` | `{:ok, {[%Domain{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DnsAnalytics.list_page/1,2,3` and `DnsAnalytics.query/1,2,3` | `{:ok, {%DnsAnalytics.Result{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DnsAnalytics.list_all/1,2,3` | `{:ok, {%DnsAnalytics.Result{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DomainResearch.get_status/2,3` | `{:ok, {%DomainResearch{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Dnssec.get/2,3` | `{:ok, {%Dnssec{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Dnssec.enable/2,3` | `{:ok, {%Dnssec{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Dnssec.disable/2,3` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Service.get/2` | `{:ok, {%Service{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Service.list_page/1,2` | `{:ok, {[%Service{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Service.list_all/1,2` | `{:ok, {[%Service{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Service.list_page_applied/2,3,4` and `Service.list_applied/2,3,4` | `{:ok, {[%Service{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Service.list_all_applied/2,3,4` | `{:ok, {[%Service{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Service.apply/3,4,5` and `Service.unapply/3,4` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Template.create/2,3` | `{:ok, {%Template{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Template.list_page/1,2,3` | `{:ok, {[%Template{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Template.list_all/1,2,3` | `{:ok, {[%Template{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Template.update/3,4` | `{:ok, {%Template{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Template.apply/3,4` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Template.delete/2,3` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `TemplateRecord.create/3,4` | `{:ok, {%TemplateRecord{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `TemplateRecord.get/3,4` | `{:ok, {%TemplateRecord{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `TemplateRecord.list_page/2,3,4` | `{:ok, {[%TemplateRecord{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `TemplateRecord.list_all/2,3,4` | `{:ok, {[%TemplateRecord{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `TemplateRecord.delete/3,4` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DelegationSignerRecord.create/3,4` | `{:ok, {%DelegationSignerRecord{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DelegationSignerRecord.get/3,4` | `{:ok, {%DelegationSignerRecord{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DelegationSignerRecord.list_page/2,3,4` | `{:ok, {[%DelegationSignerRecord{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DelegationSignerRecord.list_all/2,3,4` | `{:ok, {[%DelegationSignerRecord{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DelegationSignerRecord.delete/3,4` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `EmailForward.create/3,4` | `{:ok, {%EmailForward{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `EmailForward.get/3,4` | `{:ok, {%EmailForward{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `EmailForward.list/2,3,4` and `EmailForward.list_page/2,3,4` | `{:ok, {[%EmailForward{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `EmailForward.list_all/2,3,4` | `{:ok, {[%EmailForward{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `EmailForward.delete/3,4` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Webhook.list/1,2,3` | `{:ok, {[%Webhook{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Webhook.create/2,3` | `{:ok, {%Webhook{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Webhook.get/2,3` | `{:ok, {%Webhook{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Webhook.delete/2,3` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DomainPush.initiate/3,4` | `{:ok, {%DomainPush{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DomainPush.list_page/1,2,3` | `{:ok, {[%DomainPush{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DomainPush.list_all/1,2,3` | `{:ok, {[%DomainPush{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DomainPush.accept/3,4` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `DomainPush.reject/2,3` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.purchase_letsencrypt/2,3,4` | `{:ok, {%Certificate.Purchase{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.purchase_letsencrypt_renewal/3,4,5` | `{:ok, {%Certificate.Renewal{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.issue_letsencrypt/3,4` | `{:ok, {%Certificate{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.issue_letsencrypt_renewal/4,5` | `{:ok, {%Certificate{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.list_page/2,3,4` | `{:ok, {[%Certificate{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.list/2,3,4` | `{:ok, {[%Certificate{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.list_all/2,3,4` | `{:ok, {[%Certificate{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.get/3,4` | `{:ok, {%Certificate{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.download/3,4` | `{:ok, {%Certificate.Download{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Certificate.get_private_key/3,4` | `{:ok, {%Certificate.PrivateKey{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.check/2,3` | `{:ok, {%Registrar.CheckResult{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.get_prices/2,3` | `{:ok, {%Registrar.Prices{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.get_transfer_lock/2,3` | `{:ok, {%Registrar.TransferLock{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.enable_transfer_lock/2,3` | `{:ok, {%Registrar.TransferLock{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.disable_transfer_lock/2,3` | `{:ok, {%Registrar.TransferLock{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `RegistrantChange.create/2,3` | `{:ok, {%RegistrantChange{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `RegistrantChange.check/2,3` | `{:ok, {%RegistrantChange.CheckResult{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `RegistrantChange.get/2,3` | `{:ok, {%RegistrantChange{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `RegistrantChange.list_page/1,2,3` and `RegistrantChange.list/1,2,3` | `{:ok, {[RegistrantChange.t()], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `RegistrantChange.list_all/1,2,3` | `{:ok, {[RegistrantChange.t()], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `RegistrantChange.cancel/2,3` | `{:ok, {%RegistrantChange{}, metadata}}` or `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.enable_whois_privacy/2,3` | `{:ok, {%Registrar.WhoisPrivacy{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.disable_whois_privacy/2,3` | `{:ok, {%Registrar.WhoisPrivacy{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.register/3,4` | `{:ok, {%Registrar.Registration{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.get_registration/3,4` | `{:ok, {%Registrar.Registration{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.transfer/3,4` | `{:ok, {%Registrar.Transfer{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.get_transfer/3,4` | `{:ok, {%Registrar.Transfer{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.cancel_transfer/3,4` | `{:ok, {%Registrar.Transfer{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.renew/2,3,4` | `{:ok, {%Registrar.Renewal{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.get_renewal/3,4` | `{:ok, {%Registrar.Renewal{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.restore/2,3,4` | `{:ok, {%Registrar.Restore{}, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.get_delegation/2,3` | `{:ok, {[String.t()], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.change_delegation_to_vanity/3,4` | `{:ok, {[%VanityNameServer{}], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Registrar.change_delegation_from_vanity/2,3` | `{:ok, {nil, metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `BillingCharge.list/1,2,3` | `{:ok, {[%BillingCharge{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `BillingCharge.list_page/1,2,3` | `{:ok, {[%BillingCharge{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `BillingCharge.list_all/1,2,3` | `{:ok, {[%BillingCharge{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.get_zone_file/2,3` | `{:ok, {binary(), metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.check_zone_distribution/2,3` | `{:ok, {boolean(), metadata}}` | `{:error, %ReqDnsimple.Error{}}` |
| `Zone.update_ns_records/3,4` | `{:ok, {[%ZoneRecord{}, ...], metadata}}` | `{:error, %ReqDnsimple.Error{}}` |

`whoami/1` keeps the tagged identity as data:
`{:ok, {{:user, user}, metadata}}` or `{:ok, {{:account, account}, metadata}}`,
according to the single non-null identity, regardless of token prefix or custom
Req authentication. When both identities are present or absent, its data is
`{:unknown_token, body}`, retaining the full identity response body inside the
same success envelope, not in metadata.

`Account.list/1` returns `{:ok, {accounts, metadata}}` for its non-paginated
collection. Scoped `Zone`, `Contact`, and `BillingCharge` provide
`list_page/1,2` and `list_all/1,2`; scoped `ZoneRecord` provides `list_page/2,3`
and `list_all/2,3` with the zone argument retained. All `list` aliases use the
uniform success shape and expose metadata, but still fetch only one page.
Every `list_all` starts at page one, preserves other filters and page size,
and rejects an explicit `page` option.

### Response metadata

- `status` is the HTTP response status, including errors and bodyless successes.
- `pagination` is a nested string-keyed map. Use `metadata.pagination` and
  `metadata.pagination["current_page"]`, not `metadata["current_page"]`.
- `rate_limit` and `rate_limit_remaining` are non-negative integers when present;
  zero is not missing. `rate_limit_reset` is non-negative integer Unix seconds,
  not milliseconds, a duration, or a `DateTime`.
- `request_id`, `etag`, and `retry_after` are opaque strings. Preserve ETag
  quotes and weak `W/` prefixes; Retry-After may be a delay or an HTTP-date.
- Missing optional values are `nil`. Malformed headers or body pagination are
  explicitly recorded in `parse_errors` (default `%{}`), not silently coerced
  or converted into failed resource data. Check optional values before use.
- Single-response metadata has `pages: []`. Metadata never stores raw response
  headers or bodies wholesale.

Complete enumeration returns `{:ok, {combined_data, aggregate_metadata}}`.
`aggregate_metadata.pages` preserves every page's metadata in request order,
including empty and single-page collections. Top-level `rate_limit`,
`rate_limit_remaining`, `rate_limit_reset`, `retry_after`, and `parse_errors`
reflect the last page. Aggregate `status`, `pagination`, `request_id`, and
`etag` are `nil`: there is no fabricated collection-wide ETag or response.
Access those fields on each entry in `.pages`.

If a later HTTP request fails, `Error.metadata` retains the failing response
fields and `.pages` includes completed pages plus the failed page. A transport
failure retains prior response metadata without inventing a failed HTTP
response. No incomplete traversal returns a successful partial collection.
Malformed pagination remains visible in metadata; complete enumeration fails
explicitly if that pagination prevents a safe traversal.

Rate-limit metadata does not add automatic rate limiting, retries, or caching.
Existing request behavior, payloads, and Req configuration are unchanged.

### Explicit errors

HTTP-operation failures return
`{:error, %ReqDnsimple.Error{reason: original_reason, metadata: metadata}}`.
Generic HTTP failures retain `%{status: status, response: response_body}` in
`reason`; endpoint-specific mappings remain there when applicable. Metadata
retains all supported response fields. Retry-After lives in
`error.metadata.retry_after`, not `error.reason.retry_after`.
Local validation and transport failures have `metadata: nil` when no earlier
enumeration responses exist. An HTTP-operation `NimbleOptions.ValidationError`
is the structured error's `reason`, not an unwrapped error tuple.

Pure helpers retain their existing values: `OAuth.authorize_url/2,3` returns
`{:ok, url}` or `{:error, %NimbleOptions.ValidationError{}}` without HTTP
metadata. Client construction and re-scoping still return `Req.Request` and
raise `ArgumentError` on malformed configuration.

WHOIS privacy creation may return null `enabled` and `expires_on` values.
Both remain `nil`; a successful HTTP 201 response is not an error merely
because those values are not available yet.

### Bang Functions

`ReqDnsimple.list_zones!/1,2,3` and `Zone.list!/1,2,3` remove only the outer `:ok`
and return `{zones, metadata}` without changing their one-page request behavior.
No other endpoint has a named bang counterpart yet.

`ReqDnsimple.unwrap!/1` returns `{data, metadata}` for HTTP successes, including
`{nil, metadata}` for bodyless responses. It works uniformly with account
listing, apex NS enumeration, and tagged identity results. HTTP-operation
failures raise the same `ReqDnsimple.Error`, preserving `exception.reason` and
`exception.metadata`, including wrapped validation and transport reasons.
Its generic pure-value behavior remains: `{:ok, value}` yields `value`, `:ok`
stays `:ok`, and existing exception structs are raised unchanged. Unsupported
shapes raise `ArgumentError`; none of those generic behaviors offers a legacy
HTTP result mode.

## Common Patterns

### OAuth authorization URLs

`OAuth.authorize_url/2,3` constructs a URL locally and never resolves bearer
callbacks, performs HTTP, opens a browser, or inherits account scope. Production
uses `https://app.dnsimple.com/oauth/authorize`; sandbox uses
`https://sandbox.dnsimple.com/oauth/authorize`. Static string or `URI` HTTP(S)
base URLs are accepted, with API paths/query/fragment replaced. Custom origins
retain scheme and port with a leading `api.` removed.

```elixir
transport = ReqDnsimple.new_unscoped_client("")
state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

{:ok, url} =
  ReqDnsimple.OAuth.authorize_url(transport, "your-client-id",
    state: state,
    redirect_uri: "http://127.0.0.1:54321/callback",
    code_challenge: challenge,
    code_challenge_method: "S256"
  )
```

Applications must supply and retain an unguessable `state`, validate it on
callback, and retain the verifier for `exchange_code/2`. The builder does not
manage an OAuth session. The paired PKCE options require a 43-character
base64url challenge and method `S256`; never send a verifier or client secret
in the browser URL. Optional `account_id:` is an explicit browser account
preference, independent of client scope. Omitted options stay omitted; explicit
empty `state`/`redirect_uri` strings are forwarded, but empty state is not
suitable for an actual authorization flow. Unsupported/duplicate options and
malformed origins return validation errors.

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
{:ok, {zones, metadata}} = ReqDnsimple.Zone.list(client, page: 2, per_page: 50)
pagination = metadata.pagination

# Complete enumeration has individual response metadata, not a collection ETag.
{:ok, {all_zones, all_metadata}} = ReqDnsimple.Zone.list_all(client, per_page: 50)
page_request_ids = Enum.map(all_metadata.pages, & &1.request_id)
```

Malformed HTTP-operation option and attribute containers return
`{:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}}`
without dispatching an HTTP request.

Sort options are lists like `[:id, name: :desc]`. Supported fields are endpoint-specific:
zones accept `:id` and `:name`; records accept `:id`, `:name`, `:content`, and `:type`;
contacts accept `:id`, `:label`, and `:email`; billing charges accept only `:invoiced`.
They are automatically converted to DNSimple's `"name:asc,id:desc"` string format
by `ReqDnsimple.convert_sort_to_string/1`.

DNS analytics use the same ordered sort form for `:date`, `:zone_name`, and
`:volume`. Their `:groupings` option is an ordered list containing only `:date`
and `:zone_name`; an explicit empty list is sent as an empty query value.
`start_date` and `end_date` are ISO 8601 dates with an inclusive span of at most
31 days. Scoped `list_page/2` and `query/2` return a typed tabular result paired
with response metadata; pagination lives in `metadata.pagination`. `list_all/2`
combines only pages whose headers and echoed query settings remain compatible
and pairs the combined result with aggregate metadata.

### CRUD Operations on Zone Records

These are API reference snippets. For a runnable example that requires explicit
mutation consent and a disposable test zone, use the
[sandbox record lifecycle](samples/README.md#opt-in-mutation-one-record-lifecycle).

```elixir
# Create — attrs is a keyword list, name/type/content are required
{:ok, {record, _metadata}} = ReqDnsimple.ZoneRecord.create(client, "example.com",
  name: "www", type: "A", content: "93.184.215.14", ttl: 3600
)

# Read
{:ok, {record, _metadata}} = ReqDnsimple.ZoneRecord.get(client, "example.com", record_id)

# Update — only pass the fields you want to change
{:ok, {record, _metadata}} = ReqDnsimple.ZoneRecord.update(client, "example.com", record_id,
  content: "93.184.215.15"
)

# Delete
{:ok, {nil, _metadata}} = ReqDnsimple.ZoneRecord.delete(client, "example.com", record_id)

# Check distribution
{:ok, {distributed?, _metadata}} =
  ReqDnsimple.ZoneRecord.check_distribution(client, "example.com", record_id)

# Atomic batch; each operation list is optional
{:ok, {%ReqDnsimple.ZoneRecord.BatchResult{} = result, _metadata}} =
  ReqDnsimple.ZoneRecord.batch_change(client, "example.com",
    creates: [[name: "", type: "A", content: "192.0.2.1"]],
    updates: [[id: record_id, ttl: 0, regions: []]],
    deletes: [[id: obsolete_record_id]]
  )
```

For standalone record create and update, `ttl` and `priority` accept non-negative
integers; `priority` also accepts `nil`, transmitted unchanged as JSON `null`.
Explicit zero values are transmitted unchanged, while omitted fields remain
omitted. Batch record priorities remain non-negative integers only.
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
{:ok, {{:account, %{"id" => id}}, _metadata}} = ReqDnsimple.whoami(discovery)
client = ReqDnsimple.for_account(discovery, id)

{:ok, {zones, _metadata}} = ReqDnsimple.Zone.list(client)
```

For a user token, list accessible accounts and make an explicit user/application
selection:

```elixir
discovery = ReqDnsimple.new_unscoped_client(System.fetch_env!("DNSIMPLE_TOKEN"))
{:ok, {accounts, _metadata}} = ReqDnsimple.Account.list(discovery)
# Display account IDs, then select one deliberately.
Enum.map(accounts, & &1.id)

client = ReqDnsimple.for_account(discovery, System.fetch_env!("DNSIMPLE_ACCOUNT_ID"))
{:ok, {records, _metadata}} = ReqDnsimple.ZoneRecord.list_page(client, "example.com")
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
with exact `name=""` and `type="NS"` filters. It is read-only and returns
`{:ok, {records, metadata}}`, with `ReqDnsimple.NsRecord` structs as data and
per-page response metadata under `metadata.pages`. Apex zone records are separate
from the
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

Use `Registrar.change_delegation_to_vanity/3,4` when registrar delegation must
also change. Its required `name_servers:` keyword is encoded as a root JSON
array, and the ordered response uses `VanityNameServer` structs.
`Registrar.change_delegation_from_vanity/2,3` performs the reverse registrar
operation and returns `{:ok, {nil, metadata}}` for HTTP 204. These are distinct
from hosted-zone apex NS updates.

### Listing, Registering, Retrieving, and Deregistering Webhook Endpoints

`ReqDnsimple.Webhook.list/1,2,3` sends one bodyless request and returns the
non-paginated collection as typed webhooks. It supports ordered sorting by `id`.
Scoped `create/2` requires an absolute HTTPS callback URL and sends it unchanged
in one POST request. Scoped `get/2` sends one bodyless request and returns the
registered callback URL with its nullable suppression timestamp. Scoped
`delete/2` returns `{:ok, {nil, metadata}}`
only for HTTP 204. Retrieval and deletion accept an integer or numeric-string
webhook ID. None of these operations contacts the callback URL or inspects
deliveries.

## Module Reference

- `ReqDnsimple` — Preferred scoped creation (`new_client/2`), explicit unscoped
  creation (`new_unscoped_client/1,2`), immutable re-scoping (`for_account/2`),
  legacy unscoped creation (`new_client/1`), response-based identity
  discovery (`whoami/1`), token-prefix inspection (`token_type/1`),
  `ns_records/2,3`, convenience delegates, and `from_json/3` for JSON→struct conversion.
- `ReqDnsimple.OAuth` — Local authorization URL generation with explicit
  state/redirect/account preference and optional S256 PKCE challenge parameters.
  Unauthenticated authorization-code exchange for
  confidential clients or public clients using a 43-128 character RFC 7636
  verifier. It decodes the endpoint's unenveloped body into a typed token with
  nullable `scope`, returns `{:ok, {token, metadata}}`, and never invokes inherited
  bearer authentication.
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
  priority, and sends a flat JSON object. Known record types are accepted
  case-insensitively, including lowercase `mx`; unknown types remain errors.
  Typed responses preserve literal
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
  Older payloads may omit `expires_at`, which remains `nil`; `expires_on` is
  retained independently without inventing a timestamp.
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
  as data when asynchronous or `nil` when immediate, both with response metadata.
  Registry extended attributes
  retain string keys and values, and the registry lock-lift date may be `nil`.
  The separate `check/2,3` preflight accepts domain/contact identifiers and
  returns `CheckResult` with resolved IDs, `registry_owner_change`, and complete
  registry extended-attribute definitions as maps, without starting a change.
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
  `get_registration/3,4`, `get_renewal/3,4`, and `get_transfer/3,4` retrieve the
  existing typed lifecycle jobs by integer job ID and domain name; they neither
  resubmit nor poll. Renewal retrieval accepts current HTTP 200 and legacy 201.
  `cancel_transfer/3,4` returns a typed transfer for HTTP 202 without promising
  completed cancellation or deleting the domain. Vanity delegation changes
  accept domain names or integer IDs: `change_delegation_to_vanity/3,4` returns
  ordered typed vanity records, and `change_delegation_from_vanity/2,3` returns
  `{:ok, {nil, metadata}}`. WHOIS privacy preserves nullable enabled/expiry values.
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
- `ReqDnsimple.Metadata` — HTTP status, nested pagination, rate-limit and opaque
  header fields, per-page response metadata, and explicit metadata parse errors.
- `ReqDnsimple.Response` — Shared HTTP result formatter and `result(data)` type;
  it is not a returned response struct.
- `ReqDnsimple.Error` — Structured HTTP-operation failures retaining `reason`
  and optional response `metadata`.
- `ReqDnsimple.Helper` — `merge/2` preserves normal Req option and URL-replacement
  behavior while safely merging query maps or tuple lists by encoded key.
  `append/2` incrementally appends URL path segments and merges query/path
  parameters onto a `Req.Request`.

## Important Notes

- All API functions take a `Req.Request` client as the first argument
- Bind an explicit account ID with `new_client/2` or `for_account/2` for most
  operations; legacy explicit-account calls remain supported
- Discover account tokens through explicit `whoami/1`; discover user-token
  accounts through `Account.list/1` and explicit user/application selection
- Zone operations accept zone names (e.g., `"example.com"`) as identifiers;
  `Zone.update_ns_records/3,4` also accepts a numeric zone ID
- HTTP-operation options are validated at call time via NimbleOptions — invalid
  options return a `ReqDnsimple.Error` wrapping `NimbleOptions.ValidationError`
  with `metadata: nil`; the pure OAuth URL helper retains its direct validation error
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
only its newly created record. Never log clients, tokens, private keys, or PKCE
verifiers.
