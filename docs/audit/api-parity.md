# Approved API parity findings

These findings came from the source/offline comparison on 2026-09-11/12.
Reconfirm the selected finding against current source before changing it.
The tracker issue and its Agent Brief record the original acceptance contract.

## Current result-contract override

The approved breaking HTTP contract supersedes the historical
success-preservation requirements in CORE-002, CORE-006, CORE-008, CORE-010,
CORE-003, CORE-012, and CORE-013 below. Every supported HTTP operation now
returns `{:ok, {data, %ReqDnsimple.Metadata{}}}` or a structured
`{:error, %ReqDnsimple.Error{reason: original_reason, metadata: metadata}}`.
Bodyless success data is `nil`. Account lists and tagged identities are wrapped
uniformly; `ns_records` returns records with aggregate metadata. Bang helpers
return `{data, metadata}` and raise the structured error without stripping it.
`ReqDnsimple.Response.result(data)` describes results; `Response` is not a
returned struct.

Pagination is nested in `metadata.pagination`. Status, rate-limit fields,
request ID, opaque ETag and Retry-After strings, and explicit metadata
`parse_errors` are available for every response. Missing optional values are
`nil`; reset values are integer Unix seconds. Invalid optional metadata does
not invalidate otherwise valid resource data.

Complete enumeration keeps each response in request order under
`metadata.pages`, including empty/single-page collections. Aggregate rate-limit,
Retry-After, and parse-error fields reflect the last page; top-level status,
pagination, request ID, and ETag remain `nil`. Later HTTP failures retain the
failed response fields plus completed/failed page metadata. Transport failures
retain prior page metadata without inventing an HTTP response. Local validation
and transport errors have no HTTP metadata of their own. Metadata adds no
automatic rate limiting, retries, or caching and stores no raw headers/bodies
wholesale.

Pure helpers retain their old behavior: `OAuth.authorize_url/2,3` still returns
`{:ok, url}` or `{:error, %NimbleOptions.ValidationError{}}`; only
`OAuth.exchange_code/2` performs HTTP. Constructors still raise `ArgumentError`.
See the [current guide](../../README.md#return-value-conventions) and schema
version 2 [operation inventory](operation-inventory.json).

The findings and gate below are historical, not current return-shape guidance
or live tracker progress. The original campaign covered 103 operations; the
current supported boundary is 110 of 111 published operations, excluding only
`getDomainRestore`. Account scope still covers 102 account-path operations and
144 interface families. No endpoint, arity, provenance, or tracker membership
changes result from this response-contract migration.

## Historical correctness and compatibility findings

### CORE-001 - Preserve Bearer authentication for dynamic token callbacks

Tracker: `bd-2zx`.

**Current:** The documented zero-arity callback returns a raw token string. Req interprets that result as the entire Authorization header, so the Bearer scheme is missing.

**Required:** A callback returning a token string has the same authentication semantics as a static token. Resolve it lazily for each request, not when creating the client. Preserve compatibility with callbacks that already return a bearer tuple.

**Interfaces:** ```json
[
  "ReqDnsimple.new_client/1",
  "ReqDnsimple.token_type/1"
]
```

**Acceptance:**

- An offline adapter captures Authorization: Bearer followed by the fake token for both static tokens and raw-string callbacks.
- Existing callbacks returning a bearer tuple remain supported without a duplicated Bearer prefix.
- Two requests can resolve two successive callback values; constructing the client does not evaluate the callback.
- Update the callback typespec and dynamic-token examples to match the supported interface without printing or persisting actual credentials.

### CORE-002 - Return explicit errors for ordinary HTTP failures across existing wrappers

Tracker: `bd-1ia`.

**Current:** Eight wrappers can raise CaseClauseError for normal HTTP failures because Req returns an HTTP error response inside an ok tuple. whoami instead returns a bare failed Req.Response. ZoneRecord already has generic error branches.

**Required:** All wrappers return explicit error tuples for HTTP failures and preserve transport errors. Establish a reusable convention for subsequent API wrappers while preserving existing documented success shapes and existing specific error mappings.

**Interfaces:** ```json
[
  "All existing ReqDnsimple REST wrappers",
  "Shared request-result handling"
]
```

**Acceptance:**

- Offline cases cover every existing wrapper and representative 400, 401, 402, 403, 404, 412, 428, 429, 500, 502, 503, and 504 responses without CaseClauseError.
- Generic HTTP errors retain both status and response body, using the established ZoneRecord status/response map convention.
- Preserve existing not_found, unauthorized, timeout, and structured record-validation mappings where they are already part of the public behavior.
- whoami returns an error tuple rather than a bare failed response.
- All existing success shapes, record deletion's :ok result, and transport-error propagation remain unchanged.
- Add reusable offline request/response test helpers where needed; no Plug, real token, or live API dependency is required.
- Install a test-suite default adapter that fails closed for unmocked requests, so later tests cannot accidentally reach live API hosts.

### CORE-007 - Validate sort fields and directions while accepting documented shorthand

Tracker: `bd-1a9`.

**Current:** A malformed direction passes the outer keyword-list validation and crashes during conversion. Documented lists containing bare field atoms fail validation before reaching the converter.

**Required:** Accept the documented keyword and atom shorthand forms, validate field names and directions for each endpoint, and report malformed list options as validation errors rather than exceptions.

**Interfaces:** ```json
[
  "ReqDnsimple.convert_sort_to_string/1",
  "Existing list-option schemas"
]
```

**Acceptance:**

- Existing valid keyword sorts retain ordering and encode to the same comma-separated field:direction format.
- Bare atoms default to ascending order; mixed shorthand and keyword entries work as documented.
- Unsupported fields, unsupported directions, malformed entries, and invalid outer values return validation errors from all list entry points before HTTP.
- Allowed fields remain endpoint-specific: zones id/name; records id/name/content/type; contacts id/label/email; charges invoiced.
- The no-sort path and the public helper's existing valid-input results remain unchanged.
- Expose a reusable validation approach that later endpoint schemas can use without duplicating sort parsing.

### CORE-004 - Accept documented zero TTL and priority values in record mutations

Tracker: `bd-1eb`.

**Current:** Positive-integer validators reject ttl: 0 and priority: 0 before any request, despite the published TTL minimum and valid zero-priority records.

**Required:** Accept and transmit zero as an explicit integer value for TTL and priority on both create and update, while rejecting negative or incorrectly typed values.

**Interfaces:** ```json
[
  "ReqDnsimple.ZoneRecord.create/4",
  "ReqDnsimple.ZoneRecord.update/5"
]
```

**Acceptance:**

- The encoded POST and PATCH bodies contain numeric zero when ttl or priority is explicitly zero.
- Omitted fields remain omitted; a zero value is never converted into absence or a default.
- Negative integers, strings, and other invalid values produce validation errors before HTTP.
- Positive values and the existing required-field and apex-name behavior are preserved.

### CORE-008 - Preserve the account name in typed account responses

Tracker: `bd-vi8`.

**Current:** The account struct and whitelist omit name, losing data present in the official account examples and pinned Go SDK.

**Required:** Retain the account name as an additive struct field and reflect its possible absence in the type/documentation.

**Interfaces:** ```json
[
  "ReqDnsimple.Account",
  "ReqDnsimple.Account.from_json/1",
  "ReqDnsimple.Account.list/1"
]
```

**Acceptance:**

- An official-shaped account response retains its name after from_json and list conversion.
- Missing and null names do not crash older or alternate payloads.
- Existing fields, timestamp parsing, and the bare-list return of Account.list remain unchanged.
- The struct/typespec and account documentation include the new field and explain that the prose/SDK provide this field despite the OpenAPI omission.

### CORE-011 - Accept valid ISO8601 timezone offsets in typed responses

Tracker: `bd-5jh`.

**Current:** Timestamp conversion matches only DateTime.from_iso8601 results with a zero offset, rejecting valid nonzero offsets. Published examples use Z, so this is a contract compatibility gap, not evidence of a live incident.

**Required:** Accept every valid offset returned by DateTime.from_iso8601 while retaining normalized DateTime values, precision, and null handling.

**Interfaces:** ```json
[
  "ReqDnsimple.from_json/3",
  "Shared timestamp conversion"
]
```

**Acceptance:**

- UTC Z, positive and negative offsets, and fractional seconds decode to the expected DateTime values.
- Missing and explicitly null timestamp fields retain existing behavior.
- Malformed timestamps remain explicit errors and are never replaced by nil, the epoch, or the current time.
- Exercise the shared conversion through representative account, zone, record, contact, and billing responses.

### CORE-009 - Make billing amount and nullable-item contracts match actual values

Tracker: `bd-lih`.

**Current:** Amount fields contain decimal strings but are declared number(). Manual charge product IDs and references can be null but are specified as non-null.

**Required:** Keep exact decimal strings as the compatible runtime representation, accurately type nullable references, and document how callers can deliberately parse money if needed.

**Interfaces:** ```json
[
  "ReqDnsimple.BillingCharge",
  "ReqDnsimple.BillingCharge.Item"
]
```

**Acceptance:**

- Typespecs declare monetary strings rather than number() and permit null manual-charge product IDs/references.
- Large monetary values and trailing decimal zeroes remain byte-for-byte accurate strings after conversion.
- Nested manual items with null references decode successfully and maintain the existing structs and success shape.
- No implicit float conversion, rounding, Decimal dependency, or caller-visible representation change is introduced.

### CORE-006 - Expose pagination and complete enumeration without breaking legacy list results

Tracker: `bd-24e`.

**Current:** Zone, Contact, and BillingCharge list functions discard pagination while returning a single page. ZoneRecord.list already returns records together with pagination.

**Required:** Preserve every existing list success shape. Add explicit page-oriented and all-pages interfaces, and establish reusable pagination behavior for the new APIs. Account listing is not paginated and is excluded.

**Interfaces:** ```json
[
  "ReqDnsimple.Zone.list/3, list_page/3, list_all/3",
  "ReqDnsimple.Contact.list/3, list_page/3, list_all/3",
  "ReqDnsimple.BillingCharge.list/3, list_page/3, list_all/3",
  "ReqDnsimple.ZoneRecord.list/4, list_page/4, list_all/4"
]
```

**Acceptance:**

- Existing Zone, Contact, and BillingCharge list calls still return {:ok, items}; ZoneRecord.list still returns {:ok, {items, pagination}}.
- list_page returns {:ok, {typed_items, pagination}} with the documented string-keyed current_page, per_page, total_entries, and total_pages metadata.
- list_all returns {:ok, typed_items} from every page starting at page one, preserving filters, sorting, and per_page options.
- Reject an explicit page option on list_all rather than silently treating a partial traversal as all results; document this distinction.
- Empty collections, one-page and multi-page responses, middle-page HTTP/transport failures, and malformed/non-progressing pagination are covered.
- An incomplete traversal never returns a success-shaped partial collection, and pagination cannot cause an unbounded repeated-page loop.
- Reuse shared pagination mechanics without changing the semantics of non-paginated endpoints.

### CORE-005 - Support integrated-zone targeting consistently on record create and update

Tracker: `bd-dk5`.

**Current:** Create accepts integrated_zones, but update rejects it. Creation's arbitrary-list validation does not describe the documented integer identifiers and dnsimple sentinel.

**Required:** Support the documented mixed list of integrated-zone identifiers and the dnsimple sentinel on both operations, with deliberate omission semantics and consistent validation.

**Interfaces:** ```json
[
  "ReqDnsimple.ZoneRecord.create/4",
  "ReqDnsimple.ZoneRecord.update/5"
]
```

**Acceptance:**

- Create and update transmit a mixed list such as [1, 2, "dnsimple"] without losing the sentinel or converting integer IDs.
- Omitting integrated_zones omits the JSON field and preserves the API's existing default propagation behavior.
- Explicit list values are not silently replaced with a default target; invalid item types fail validation before HTTP.
- Tests cover both request methods, omission, the dnsimple-only selection, mixed selections, and API/transport failures.
- Explain the published prose/schema discrepancy: prose supports the dnsimple sentinel despite the integer-only OpenAPI item declaration.

### CORE-010 - Determine authenticated identity from the response rather than token prefixes

Tracker: `bd-1y1`.

**Current:** whoami inspects token spelling and can report an unknown token despite a successful identified account. It also resolves dynamic authentication a second time solely to classify identity.

**Required:** Return the existing user/account tuple forms based on the successful response's non-null identity. Leave token_type as a separate prefix-inspection utility, not an identity authority.

**Interfaces:** ```json
[
  "ReqDnsimple.whoami/1",
  "ReqDnsimple.token_type/1"
]
```

**Acceptance:**

- Opaque, user-prefixed, account-prefixed, and dynamically supplied credentials all select the response's actual user-only or account-only identity.
- A successful whoami request evaluates a dynamic token callback only as needed for authentication, not again for classification.
- Preserve {:user, data} and {:account, data}; preserve all response data in the existing {:unknown_token, body} fallback for neither/both identity modes and document that fallback.
- Custom Req authentication configurations do not cause token_type function-clause failures inside whoami.
- HTTP and transport failures follow CORE-002, without exposing credentials in error messages.

### CORE-003 - Replace the unsupported NS read route with read-only apex record enumeration

Tracker: `bd-1fw`.

**Current:** ns_records issues GET on the path documented only for PUT zone NS updates. It is not a wrapper for a documented read operation.

**Required:** Read apex NS records through the zone-record listing API with exact empty name and NS type filters, following all pages. Preserve the existing bare list of NsRecord structs on success. Keep this helper strictly read-only.

**Interfaces:** ```json
[
  "ReqDnsimple.ns_records/3",
  "ReqDnsimple.NsRecord",
  "ReqDnsimple.ZoneRecord.list_all/4"
]
```

**Acceptance:**

- Captured requests use GET on the zone records collection, with type=NS and name equal to the empty string.
- A multi-page fixture returns every apex NS record, with typed timestamps and a string zone_id.
- The public ns_records/3 success shape remains a bare list of NsRecord structs and failures use the established error convention.
- No request targets the unsupported GET ns_records route and no PUT, POST, PATCH, or DELETE is issued.
- Document the distinction between apex zone records, registrar delegation, and the separate explicit zone-NS-update API.

### CORE-012 - Align public typespecs and nullability with preserved runtime contracts

Tracker: `bd-3fj`.

**Current:** Several specs omit error results or describe the wrong success wrapper; callback input, nullable zone timestamps, and NS zone identifiers also disagree with runtime behavior.

**Required:** Make the existing public type contracts accurately describe the final compatible behavior after the foundational fixes, without changing runtime shapes to satisfy typespecs.

**Interfaces:** ```json
[
  "Public ReqDnsimple typespecs",
  "Existing resource structs and wrapper return types"
]
```

**Acceptance:**

- Contact.get, record get/delete, whoami, ns_records, lists, and callback-client construction advertise their actual success and error forms.
- Nullable fields such as last_transferred_at and parent/priority fields are accurately represented; zone-record zone_id values are strings.
- Keep Account.list and ns_records bare-list successes, existing ok tuples, record pagination tuples, and deletion's :ok result intact.
- Inspect public specs against representative executable examples and retain compilation without new project warnings.
- Do not introduce a type checker or new runtime dependency solely for this issue.

### CORE-013 - Make README and usage rules accurately describe coverage and contracts

Tracker: `bd-2tb`.

**Current:** usage-rules claims all DNSimple operations are supported. Dynamic auth, sorting, error, pagination, and billing type guidance also needs to match the corrected behavior.

**Required:** Describe implemented functionality truthfully, distinguish existing success conventions from new additive APIs, and make the bounded campaign scope and remaining unlisted APIs discoverable.

**Interfaces:** ```json
[
  "README API module catalog and examples",
  "usage-rules coverage and return-value guidance",
  "Versioned API coverage inventory"
]
```

**Acceptance:**

- Remove the claim of complete DNSimple API coverage while any published operation remains unimplemented or outside scope.
- Examples accurately cover dynamic token callbacks, legacy lists versus list_page/list_all, error tuples, valid sort forms, NS reads versus mutations, and decimal-string billing amounts.
- Published code examples and module/function references correspond to actual exports and covered behavior.
- Point readers to the versioned operation inventory, clearly distinguishing implemented, campaign-pending, and explicitly out-of-scope operations.
- Preserve the library's lightweight Req/NimbleOptions positioning; do not describe CLI confirmations or browser UI as library features.

## Historical missing operations in scope

Each row is one independently complete API issue. Base URL includes `/v2`.
Counts exclude command aliases, convenience delegates, and local CLI UI.

| Finding | br issue | Operation | Method | Path |
|---|---|---|---|---|
| API-001 | bd-2ch | `acceptPush` | POST | `/{account}/pushes/{push}` |
| API-002 | bd-2j2 | `activateZoneService` | PUT | `/{account}/zones/{zone}/activation` |
| API-003 | bd-2pz | `applyServiceToDomain` | POST | `/{account}/domains/{domain}/services/{service}` |
| API-004 | bd-14h | `applyTemplateToDomain` | POST | `/{account}/domains/{domain}/templates/{template}` |
| API-005 | bd-212 | `authorizeDomainTransferOut` | POST | `/{account}/registrar/domains/{domain}/authorize_transfer_out` |
| API-006 | bd-1jv | `batchChangeZoneRecords` | POST | `/{account}/zones/{zone}/batch` |
| API-007 | bd-19i | `changeDomainDelegation` | PUT | `/{account}/registrar/domains/{domain}/delegation` |
| API-008 | bd-3dl | `checkDomain` | GET | `/{account}/registrar/domains/{domain}/check` |
| API-009 | bd-12p | `checkZoneRecordDistribution` | GET | `/{account}/zones/{zone}/records/{zonerecord}/distribution` |
| API-010 | bd-32n | `createContact` | POST | `/{account}/contacts` |
| API-011 | bd-2wb | `createDomain` | POST | `/{account}/domains` |
| API-012 | bd-3mq | `createDomainDelegationSignerRecord` | POST | `/{account}/domains/{domain}/ds_records` |
| API-013 | bd-3rn | `createEmailForward` | POST | `/{account}/domains/{domain}/email_forwards` |
| API-014 | bd-22q | `createPrimaryServer` | POST | `/{account}/secondary_dns/primaries` |
| API-015 | bd-300 | `createRegistrantChange` | POST | `/{account}/registrar/registrant_changes` |
| API-016 | bd-cke | `createSecondaryZone` | POST | `/{account}/secondary_dns/zones` |
| API-017 | bd-2jb | `createTemplate` | POST | `/{account}/templates` |
| API-018 | bd-3t5 | `createTemplateRecord` | POST | `/{account}/templates/{template}/records` |
| API-019 | bd-2en | `createWebhook` | POST | `/{account}/webhooks` |
| API-020 | bd-3u4 | `deactivateZoneService` | DELETE | `/{account}/zones/{zone}/activation` |
| API-021 | bd-3aj | `deleteContact` | DELETE | `/{account}/contacts/{contact}` |
| API-022 | bd-17c | `deleteDomain` | DELETE | `/{account}/domains/{domain}` |
| API-023 | bd-fcp | `deleteDomainDelegationSignerRecord` | DELETE | `/{account}/domains/{domain}/ds_records/{ds}` |
| API-024 | bd-nqj | `deleteEmailForward` | DELETE | `/{account}/domains/{domain}/email_forwards/{emailforward}` |
| API-025 | bd-2ao | `deleteRegistrantChange` | DELETE | `/{account}/registrar/registrant_changes/{registrantchange}` |
| API-026 | bd-275 | `deleteTemplate` | DELETE | `/{account}/templates/{template}` |
| API-027 | bd-2q9 | `deleteTemplateRecord` | DELETE | `/{account}/templates/{template}/records/{templaterecord}` |
| API-028 | bd-2xo | `deleteWebhook` | DELETE | `/{account}/webhooks/{webhook}` |
| API-029 | bd-9kx | `disableDomainAutoRenewal` | DELETE | `/{account}/registrar/domains/{domain}/auto_renewal` |
| API-030 | bd-2hd | `disableDomainDnssec` | DELETE | `/{account}/domains/{domain}/dnssec` |
| API-031 | bd-3rf | `disableDomainTransferLock` | DELETE | `/{account}/registrar/domains/{domain}/transfer_lock` |
| API-032 | bd-yha | `disableVanityNameServers` | DELETE | `/{account}/vanity/{domain}` |
| API-033 | bd-1zz | `disableWhoisPrivacy` | DELETE | `/{account}/registrar/domains/{domain}/whois_privacy` |
| API-034 | bd-n3l | `domainRenew` | POST | `/{account}/registrar/domains/{domain}/renewals` |
| API-035 | bd-3qa | `domainRestore` | POST | `/{account}/registrar/domains/{domain}/restores` |
| API-036 | bd-2af | `downloadCertificate` | GET | `/{account}/domains/{domain}/certificates/{certificate}/download` |
| API-037 | bd-3an | `enableDomainAutoRenewal` | PUT | `/{account}/registrar/domains/{domain}/auto_renewal` |
| API-038 | bd-26w | `enableDomainDnssec` | POST | `/{account}/domains/{domain}/dnssec` |
| API-039 | bd-2tx | `enableDomainTransferLock` | POST | `/{account}/registrar/domains/{domain}/transfer_lock` |
| API-040 | bd-qw8 | `enableVanityNameServers` | PUT | `/{account}/vanity/{domain}` |
| API-041 | bd-zkj | `enableWhoisPrivacy` | PUT | `/{account}/registrar/domains/{domain}/whois_privacy` |
| API-042 | bd-ub4 | `getCertificate` | GET | `/{account}/domains/{domain}/certificates/{certificate}` |
| API-043 | bd-1ef | `getCertificatePrivateKey` | GET | `/{account}/domains/{domain}/certificates/{certificate}/private_key` |
| API-044 | bd-1ru | `getDomain` | GET | `/{account}/domains/{domain}` |
| API-045 | bd-o6d | `getDomainDelegation` | GET | `/{account}/registrar/domains/{domain}/delegation` |
| API-046 | bd-2eg | `getDomainDelegationSignerRecord` | GET | `/{account}/domains/{domain}/ds_records/{ds}` |
| API-047 | bd-l4k | `getDomainDnssec` | GET | `/{account}/domains/{domain}/dnssec` |
| API-048 | bd-3uw | `getDomainPrices` | GET | `/{account}/registrar/domains/{domain}/prices` |
| API-049 | bd-3aq | `getDomainTransferLock` | GET | `/{account}/registrar/domains/{domain}/transfer_lock` |
| API-050 | bd-3br | `getDomainsResearchStatus` | GET | `/{account}/domains/research/status` |
| API-051 | bd-cln | `getEmailForward` | GET | `/{account}/domains/{domain}/email_forwards/{emailforward}` |
| API-052 | bd-7ip | `getPrimaryServer` | GET | `/{account}/secondary_dns/primaries/{primaryserver}` |
| API-053 | bd-13h | `getRegistrantChange` | GET | `/{account}/registrar/registrant_changes/{registrantchange}` |
| API-054 | bd-yhr | `getService` | GET | `/services/{service}` |
| API-055 | bd-cdm | `getTemplate` | GET | `/{account}/templates/{template}` |
| API-056 | bd-3v1 | `getTemplateRecord` | GET | `/{account}/templates/{template}/records/{templaterecord}` |
| API-057 | bd-2y0 | `getTld` | GET | `/tlds/{tld}` |
| API-058 | bd-3ip | `getTldExtendedAttributes` | GET | `/tlds/{tld}/extended_attributes` |
| API-059 | bd-10h | `getWebhook` | GET | `/{account}/webhooks/{webhook}` |
| API-060 | bd-35r | `getZone` | GET | `/{account}/zones/{zone}` |
| API-061 | bd-3g2 | `initiateDomainPush` | POST | `/{account}/domains/{domain}/pushes` |
| API-062 | bd-18g | `issueLetsencryptCertificate` | POST | `/{account}/domains/{domain}/certificates/letsencrypt/{purchaseId}/issue` |
| API-063 | bd-17f | `issueRenewalLetsencryptCertificate` | POST | `/{account}/domains/{domain}/certificates/letsencrypt/{certificate}/renewals/{renewalId}/issue` |
| API-064 | bd-17x | `linkPrimaryServer` | PUT | `/{account}/secondary_dns/primaries/{primaryserver}/link` |
| API-065 | bd-2su | `listCertificates` | GET | `/{account}/domains/{domain}/certificates` |
| API-066 | bd-2oj | `listDomainAppliedServices` | GET | `/{account}/domains/{domain}/services` |
| API-067 | bd-2rx | `listDomainDelegationSignerRecords` | GET | `/{account}/domains/{domain}/ds_records` |
| API-068 | bd-xei | `listDomains` | GET | `/{account}/domains` |
| API-069 | bd-118 | `listEmailForwards` | GET | `/{account}/domains/{domain}/email_forwards` |
| API-070 | bd-36i | `listPrimaryServers` | GET | `/{account}/secondary_dns/primaries` |
| API-071 | bd-fjb | `listPushes` | GET | `/{account}/pushes` |
| API-072 | bd-186 | `listRegistrantChanges` | GET | `/{account}/registrar/registrant_changes` |
| API-073 | bd-1qj | `listServices` | GET | `/services` |
| API-074 | bd-1a6 | `listTemplateRecords` | GET | `/{account}/templates/{template}/records` |
| API-075 | bd-1x9 | `listTemplates` | GET | `/{account}/templates` |
| API-076 | bd-2md | `listTlds` | GET | `/tlds` |
| API-077 | bd-3j7 | `listWebhooks` | GET | `/{account}/webhooks` |
| API-078 | bd-21n | `oauthToken` | POST | `/oauth/access_token` |
| API-079 | bd-lgq | `purchaseLetsencryptCertificate` | POST | `/{account}/domains/{domain}/certificates/letsencrypt` |
| API-080 | bd-3g9 | `purchaseRenewalLetsencryptCertificate` | POST | `/{account}/domains/{domain}/certificates/letsencrypt/{certificate}/renewals` |
| API-081 | bd-1jq | `queryDnsAnalytics` | GET | `/{account}/dns_analytics` |
| API-082 | bd-1f7 | `registerDomain` | POST | `/{account}/registrar/domains/{domain}/registrations` |
| API-083 | bd-2kp | `rejectPush` | DELETE | `/{account}/pushes/{push}` |
| API-084 | bd-3cd | `removePrimaryServer` | DELETE | `/{account}/secondary_dns/primaries/{primaryserver}` |
| API-085 | bd-35c | `transferDomain` | POST | `/{account}/registrar/domains/{domain}/transfers` |
| API-086 | bd-3os | `unapplyServiceFromDomain` | DELETE | `/{account}/domains/{domain}/services/{service}` |
| API-087 | bd-131 | `unlinkPrimaryServer` | PUT | `/{account}/secondary_dns/primaries/{primaryserver}/unlink` |
| API-088 | bd-1cx | `updateContact` | PATCH | `/{account}/contacts/{contact}` |
| API-089 | bd-es2 | `updateTemplate` | PATCH | `/{account}/templates/{template}` |
| API-090 | bd-39k | `updateZoneNsRecords` | PUT | `/{account}/zones/{zone}/ns_records` |

## Explicitly outside this campaign

The maintainer originally chose the listed audit scope rather than full public
API coverage. These additional published operations were excluded from that
campaign:

- `cancelDomainTransfer`
- `changeDomainDelegationFromVanity`
- `changeDomainDelegationToVanity`
- `checkRegistrantChange`
- `getDomainRegistration`
- `getDomainRenewal`
- `getDomainRestore`
- `getDomainTransfer`

The separately approved official Elixir SDK-parity extension on 2026-09-15
implements seven of these operations; only `getDomainRestore` remains
`out-of-scope`. The current [operation inventory](operation-inventory.json)
therefore records 110 supported operations. The historical campaign gate below
retains its original scope.

## Historical completion gate

`bd-26j` (VERIFY-001) waits for all 103 implementation
issues and verifies actual HTTP contracts, compatibility, documentation, and
the 103-operation inventory. Export counts alone do not satisfy the gate.
