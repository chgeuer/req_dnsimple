# ReqDnsimple domain model

## Client

A client is a `Req.Request` carrying authentication, transport configuration,
and an optional selected DNSimple account. Selecting an account is local and
does not discover accounts or verify permissions.

## HTTP operation

An HTTP operation calls a DNSimple endpoint. Its result is
`{:ok, {data, metadata}}` or `{:error, %ReqDnsimple.Error{}}`. A bodyless success
has `nil` data. Pure helpers, including client construction and OAuth
authorization URL generation, do not acquire HTTP response metadata.

## Response metadata

`ReqDnsimple.Metadata` contains the returned HTTP status, nested pagination,
rate-limit budget and reset information, request ID, ETag, and Retry-After.
Pagination remains a string-keyed map under `metadata.pagination`.
`rate_limit`, `rate_limit_remaining`, and `rate_limit_reset` are non-negative
integers when present; reset times are Unix seconds, not milliseconds.
Request IDs, ETags (including quotes/weak prefixes), and Retry-After (delay or
HTTP-date) retain their opaque strings. Missing optional values are `nil`;
malformed metadata is exposed in `parse_errors`, not treated as failed resource
data. A single response defaults to `pages: []` and `parse_errors: %{}`.
Metadata stores no raw headers or bodies wholesale and adds no automatic rate
limiting, retries, or caching. `ReqDnsimple.Response.result(data)` is a shared
result type/formatter, not a returned struct.

## Complete enumeration

`list_all` combines data from successive pages and retains their metadata in
request order under `metadata.pages`. Aggregate budget values come from the
last page, as do Retry-After and metadata parse errors. Empty and single-page
collections still retain each response in `.pages`. No single status,
pagination object, request ID, or ETag represents the combined collection;
those aggregate fields are `nil`. Read-only apex `ns_records` enumeration uses
the same aggregate contract.

## Failure

`ReqDnsimple.Error` retains the original failure reason and any available
metadata. A local validation or transport failure has no HTTP response of its
own. If enumeration already received earlier pages, their metadata is retained
even when a later request fails. A later HTTP failure retains the failing
response fields and completed plus failed pages; a transport failure fabricates
no failure response. Generic HTTP failure reasons retain status and response
body; Retry-After is in metadata, not the reason. Bang helpers strip only `:ok`,
return `{data, metadata}`, and raise the structured error without losing its
reason or metadata.

## Pure helper

Pure helpers do not perform HTTP and do not use the HTTP result envelope.
`OAuth.authorize_url/2,3` remains `{:ok, url}` or
`{:error, %NimbleOptions.ValidationError{}}`. Constructors and `for_account/2`
return `Req.Request` and still raise `ArgumentError` on invalid configuration.
`OAuth.exchange_code/2` is an HTTP operation, returning a token with metadata.
`whoami/1` is also HTTP; its existing user, account, or unknown identity tag is
the data inside the uniform success tuple.
