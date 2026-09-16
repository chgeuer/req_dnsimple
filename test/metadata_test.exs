defmodule ReqDnsimple.MetadataTest do
  use ExUnit.Case, async: true

  alias ReqDnsimple.{Error, Metadata, Response}

  @pagination %{
    "current_page" => 1,
    "per_page" => 30,
    "total_entries" => 45,
    "total_pages" => 2
  }

  test "HTTP metadata retains pagination, numeric budgets, and opaque header values" do
    response =
      Req.Response.new(
        status: 200,
        body: %{"data" => [], "pagination" => @pagination},
        headers: [
          {"X-RateLimit-Limit", "2400"},
          {"X-RateLimit-Remaining", "0"},
          {"X-RateLimit-Reset", "1790000000"},
          {"X-Request-ID", "request-one"},
          {"ETag", ~s(W/"opaque+tag")},
          {"Retry-After", "60"}
        ]
      )

    assert %Metadata{
             status: 200,
             pagination: @pagination,
             rate_limit: 2400,
             rate_limit_remaining: 0,
             rate_limit_reset: 1_790_000_000,
             request_id: "request-one",
             etag: ~s(W/"opaque+tag"),
             retry_after: "60",
             pages: [],
             parse_errors: %{}
           } = Metadata.from_response(response)
  end

  test "missing optional metadata stays nil, including on bodyless success" do
    response = Req.Response.new(status: 204, body: "")
    assert Metadata.from_response(response) == %Metadata{status: 204}
    assert Response.ok(nil, response) == {:ok, {nil, %Metadata{status: 204}}}
  end

  test "malformed and ambiguous headers remain explicit without failing successful data" do
    response = %Req.Response{
      status: 200,
      body: %{"data" => [1], "pagination" => "invalid"},
      headers: [
        {"X-RateLimit-Limit", "-1"},
        {"X-RateLimit-Remaining", "12oops"},
        {"X-RateLimit-Reset", "not-a-timestamp"},
        {"X-Request-ID", "first"},
        {"x-request-id", "second"},
        {"Retry-After", "Wed, 21 Oct 2015 07:28:00 GMT"}
      ]
    }

    assert {:ok, {[1], %Metadata{} = metadata}} = Response.ok([1], response)
    assert metadata.rate_limit == nil
    assert metadata.rate_limit_remaining == nil
    assert metadata.rate_limit_reset == nil
    assert metadata.request_id == nil
    assert metadata.pagination == nil
    assert metadata.retry_after == "Wed, 21 Oct 2015 07:28:00 GMT"

    assert metadata.parse_errors == %{
             rate_limit: {:invalid_header, ["-1"]},
             rate_limit_remaining: {:invalid_header, ["12oops"]},
             rate_limit_reset: {:invalid_header, ["not-a-timestamp"]},
             request_id: {:invalid_header, ["first", "second"]},
             pagination: {:invalid_pagination, "invalid"}
           }
  end

  test "header names are case-insensitive and numeric header whitespace is accepted" do
    response = %Req.Response{
      status: 200,
      headers: %{
        "X-RATELIMIT-LIMIT" => [" 2400 "],
        "x-RateLimit-Remaining" => ["2399"],
        "X-REQUEST-ID" => ["case-preserved-value"],
        "ETAG" => [~s("opaque")]
      }
    }

    metadata = Metadata.from_response(response)
    assert metadata.rate_limit == 2400
    assert metadata.rate_limit_remaining == 2399
    assert metadata.request_id == "case-preserved-value"
    assert metadata.etag == ~s("opaque")
    assert metadata.parse_errors == %{}
  end

  test "aggregate metadata retains every page without inventing a collection ETag or request ID" do
    first = page_metadata(1, 2399)
    last = page_metadata(2, 2398)
    metadata = Metadata.aggregate([first, last])

    assert metadata.pages == [first, last]
    assert metadata.rate_limit == 2400
    assert metadata.rate_limit_remaining == 2398
    assert metadata.rate_limit_reset == last.rate_limit_reset
    assert metadata.retry_after == last.retry_after
    assert metadata.status == nil
    assert metadata.pagination == nil
    assert metadata.request_id == nil
    assert metadata.etag == nil
    assert Enum.map(metadata.pages, & &1.request_id) == ["page-1", "page-2"]
    assert Enum.map(metadata.pages, & &1.etag) == [~s("page-1"), ~s("page-2")]
    assert Enum.all?(metadata.pages, &(&1.pages == []))
  end

  test "HTTP failures retain response metadata and their original reason" do
    response =
      Req.Response.new(status: 404, headers: [{"x-request-id", "missing-request"}])

    assert {:error,
            %Error{
              reason: :not_found,
              metadata: %Metadata{status: 404, request_id: "missing-request"}
            }} = Response.error(:not_found, response)
  end

  test "local and transport failures have no HTTP metadata and normalization is idempotent" do
    reason = %Req.TransportError{reason: :timeout}
    assert {:error, %Error{reason: ^reason, metadata: nil}} = result = Response.error(reason)
    assert Response.normalize_error(result) == result

    assert {:error, %Error{reason: :missing_account_id, metadata: nil}} =
             Response.normalize_error({:error, :missing_account_id})
  end

  test "failed enumeration keeps completed pages and the failing HTTP response" do
    first = page_metadata(1, 1)

    failed =
      Req.Response.new(
        status: 429,
        headers: [
          {"x-ratelimit-remaining", "0"},
          {"x-request-id", "failed-page"},
          {"retry-after", "90"}
        ]
      )

    {:error, error} = Response.error(:rate_limited, failed)
    assert {:error, %Error{} = error} = Response.error_after_pages(error, [first])
    assert error.metadata.status == 429
    assert error.metadata.request_id == "failed-page"
    assert error.metadata.rate_limit_remaining == 0
    assert error.metadata.retry_after == "90"
    assert Enum.map(error.metadata.pages, & &1.request_id) == ["page-1", "failed-page"]
  end

  test "enumeration transport failure retains prior metadata but no fabricated failed response" do
    first = page_metadata(1, 2399)
    {:error, error} = Response.error(%Req.TransportError{reason: :timeout})

    assert Response.error_after_pages(error, []) == {:error, error}
    assert {:error, %Error{metadata: metadata}} = Response.error_after_pages(error, [first])
    assert metadata.pages == [first]
    assert metadata.status == nil
    assert metadata.request_id == nil
    assert metadata.etag == nil
    assert metadata.rate_limit_remaining == 2399
  end

  defp page_metadata(page, remaining) do
    Req.Response.new(
      status: 200,
      body: %{"pagination" => %{@pagination | "current_page" => page}},
      headers: [
        {"x-ratelimit-limit", "2400"},
        {"x-ratelimit-remaining", Integer.to_string(remaining)},
        {"x-ratelimit-reset", "1790000000"},
        {"x-request-id", "page-#{page}"},
        {"etag", ~s("page-#{page}")}
      ]
    )
    |> Metadata.from_response()
  end
end
