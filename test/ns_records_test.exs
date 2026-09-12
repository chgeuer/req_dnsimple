defmodule ReqDnsimple.NsRecordsTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  test "returns every apex NS record through the read-only zone records API" do
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

      {request, %Req.Response{status: 200, body: body}}
    end

    client =
      ReqDnsimple.new_client("dnsimple_u_fake-token")
      |> Req.merge(adapter: adapter, retry: false)

    assert [
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
           ] = ReqDnsimple.ns_records(client, 1010, "example.com")

    query = %{"name" => "", "type" => "NS"}
    assert_request(:get, "/v2/1010/zones/example.com/records", Map.put(query, "page", 1))
    assert_request(:get, "/v2/1010/zones/example.com/records", Map.put(query, "page", 2))
    refute_receive {:request, _request}
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
