defmodule ReqDnsimple.NsRecordsTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  alias ReqDnsimple.{Error, Metadata}

  test "returns every apex NS record with per-page metadata through the read-only zone records API" do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request})

      body =
        case URI.decode_query(request.url.query || "") do
          %{"page" => "1"} ->
            page(
              [ns_record(1, "ns1.dnsimple.com", "2024-01-01T00:00:00Z")],
              1,
              2
            )

          %{"page" => "2"} ->
            page([ns_record(2, "ns2.dnsimple.com", "2024-01-02T00:00:00Z")], 2, 2)
        end

      page = body["pagination"]["current_page"]

      {request,
       Req.Response.new(
         status: 200,
         body: body,
         headers: [
           {"x-request-id", "ns-page-#{page}"},
           {"etag", ~s("ns-page-#{page}")},
           {"x-ratelimit-limit", "100"},
           {"x-ratelimit-remaining", to_string(100 - page)},
           {"x-ratelimit-reset", "1790000000"},
           {"retry-after", "15"}
         ]
       )}
    end

    client =
      ReqDnsimple.new_client("dnsimple_u_fake-token")
      |> Req.merge(adapter: adapter, retry: false)

    assert {:ok,
            {[
               %ReqDnsimple.NsRecord{
                 id: 1,
                 zone_id: "example.com",
                 name: "",
                 content: "ns1.dnsimple.com",
                 type: "NS",
                 created_at: %DateTime{}
               },
               %ReqDnsimple.NsRecord{
                 id: 2,
                 zone_id: "example.com",
                 name: "",
                 content: "ns2.dnsimple.com",
                 type: "NS",
                 updated_at: %DateTime{}
               }
             ], %Metadata{} = metadata}} = ReqDnsimple.ns_records(client, 1010, "example.com")

    assert metadata == %Metadata{
             rate_limit: 100,
             rate_limit_remaining: 98,
             rate_limit_reset: 1_790_000_000,
             retry_after: "15",
             pages:
               for page <- 1..2 do
                 %Metadata{
                   status: 200,
                   pagination: %{
                     "current_page" => page,
                     "per_page" => 1,
                     "total_entries" => 2,
                     "total_pages" => 2
                   },
                   request_id: "ns-page-#{page}",
                   etag: ~s("ns-page-#{page}"),
                   rate_limit: 100,
                   rate_limit_remaining: 100 - page,
                   rate_limit_reset: 1_790_000_000,
                   retry_after: "15"
                 }
               end
           }

    query = %{"name" => "", "type" => "NS"}
    assert_request(:get, "/v2/1010/zones/example.com/records", Map.put(query, "page", 1))
    assert_request(:get, "/v2/1010/zones/example.com/records", Map.put(query, "page", 2))
    refute_receive {:request, _request}
  end

  test "retains the sole page's metadata for empty and single-page NS results" do
    for records <- [[], [ns_record(1, "ns1.dnsimple.com", "2024-01-01T00:00:00Z")]] do
      pagination = %{
        "current_page" => 1,
        "per_page" => 100,
        "total_entries" => length(records),
        "total_pages" => 1
      }

      req =
        client(200, %{"data" => records, "pagination" => pagination}, self(), [
          {"x-request-id", "only-ns-page"}
        ])

      assert {:ok, {data, %Metadata{} = metadata}} =
               ReqDnsimple.ns_records(req, 1010, "example.com")

      assert Enum.map(data, & &1.id) == Enum.map(records, & &1["id"])
      assert Enum.all?(data, &is_struct(&1, ReqDnsimple.NsRecord))

      assert metadata == %Metadata{
               pages: [
                 %Metadata{status: 200, pagination: pagination, request_id: "only-ns-page"}
               ]
             }

      assert_request(:get, "/v2/1010/zones/example.com/records", %{
        "name" => "",
        "type" => "NS",
        "page" => 1
      })

      refute_received {:request, _request}
    end
  end

  test "retains prior pages and real failed HTTP responses when NS enumeration fails" do
    test_pid = self()
    first_body = page([ns_record(1, "ns1.dnsimple.com", "2024-01-01T00:00:00Z")], 1, 2)

    first_metadata = %Metadata{
      status: 200,
      pagination: first_body["pagination"],
      request_id: "first-ns-page",
      rate_limit_remaining: 10
    }

    for failure <- [:http, :transport] do
      req =
        ReqDnsimple.new_client("dnsimple_u_fake-token")
        |> Req.merge(
          retry: false,
          adapter: fn request ->
            send(test_pid, {:request, request})

            response =
              case URI.decode_query(request.url.query || "") do
                %{"page" => "1"} ->
                  Req.Response.new(
                    status: 200,
                    body: first_body,
                    headers: [
                      {"x-request-id", "first-ns-page"},
                      {"x-ratelimit-remaining", "10"}
                    ]
                  )

                %{"page" => "2"} when failure == :http ->
                  Req.Response.new(
                    status: 429,
                    body: %{"message" => "Rate limited"},
                    headers: [
                      {"x-request-id", "failed-ns-page"},
                      {"x-ratelimit-remaining", "0"},
                      {"retry-after", "60"}
                    ]
                  )

                %{"page" => "2"} when failure == :transport ->
                  %Req.TransportError{reason: :econnrefused}
              end

            {request, response}
          end
        )

      assert {:error, %Error{} = error} = ReqDnsimple.ns_records(req, 1010, "example.com")

      if failure == :http do
        assert error == %Error{
                 reason: %{status: 429, response: %{"message" => "Rate limited"}},
                 metadata: %Metadata{
                   status: 429,
                   request_id: "failed-ns-page",
                   rate_limit_remaining: 0,
                   retry_after: "60",
                   pages: [
                     first_metadata,
                     %Metadata{
                       status: 429,
                       request_id: "failed-ns-page",
                       rate_limit_remaining: 0,
                       retry_after: "60"
                     }
                   ]
                 }
               }
      else
        assert error == %Error{
                 reason: %Req.TransportError{reason: :econnrefused},
                 metadata: %Metadata{
                   rate_limit_remaining: 10,
                   pages: [first_metadata]
                 }
               }
      end

      for page <- 1..2 do
        assert_request(:get, "/v2/1010/zones/example.com/records", %{
          "name" => "",
          "type" => "NS",
          "page" => page
        })
      end

      refute_received {:request, _request}
    end
  end

  defp page(data, current_page, total_pages) do
    %{
      "data" => data,
      "pagination" => %{
        "current_page" => current_page,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => total_pages
      }
    }
  end

  defp ns_record(id, content, created_at) do
    %{
      "id" => id,
      "zone_id" => "example.com",
      "parent_id" => nil,
      "name" => "",
      "content" => content,
      "ttl" => 3600,
      "priority" => nil,
      "type" => "NS",
      "regions" => ["global"],
      "system_record" => true,
      "created_at" => created_at,
      "updated_at" => "2024-01-03T00:00:00Z"
    }
  end
end
