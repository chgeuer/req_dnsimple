defmodule ReqDnsimple.DnsAnalyticsTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  alias ReqDnsimple.DnsAnalytics
  alias ReqDnsimple.DnsAnalytics.Query
  alias ReqDnsimple.DnsAnalytics.Result
  alias ReqDnsimple.{Error, Metadata}

  @data %{
    "headers" => ["date", "zone_name", "volume"],
    "rows" => [["2026-09-02", "example.test", 1200]]
  }

  @query %{
    "account_id" => 1010,
    "start_date" => "2026-09-01",
    "end_date" => "2026-09-02",
    "groupings" => "date,zone_name",
    "sort" => "date:asc,zone_name:desc",
    "page" => 2,
    "per_page" => 1
  }

  @pagination %{
    "current_page" => 2,
    "per_page" => 1,
    "total_entries" => 2,
    "total_pages" => 2
  }

  describe "list_page/3 and query/3" do
    test "queryDnsAnalytics sends filters once and decodes the typed tabular result" do
      body = %{"data" => @data, "query" => @query, "pagination" => @pagination}

      assert {:ok,
              {%Result{
                 headers: ["date", "zone_name", "volume"],
                 rows: [["2026-09-02", "example.test", 1200]],
                 query: %Query{
                   account_id: 1010,
                   start_date: ~D[2026-09-01],
                   end_date: ~D[2026-09-02],
                   groupings: "date,zone_name",
                   sort: "date:asc,zone_name:desc",
                   page: 2,
                   per_page: 1
                 }
               }, %Metadata{status: 200, pagination: @pagination}}} =
               DnsAnalytics.list_page(
                 client(200, body),
                 1010,
                 start_date: "2026-09-01",
                 end_date: "2026-09-02",
                 groupings: [:date, :zone_name],
                 sort: [date: :asc, zone_name: :desc],
                 page: 2,
                 per_page: 1
               )

      assert_request(:get, "/v2/1010/dns_analytics", %{
        "start_date" => "2026-09-01",
        "end_date" => "2026-09-02",
        "groupings" => "date,zone_name",
        "sort" => "date:asc,zone_name:desc",
        "page" => 2,
        "per_page" => 1
      })

      refute_received {:request, _request}
    end

    test "queryDnsAnalytics alias requests exactly one page" do
      body = %{"data" => @data, "query" => @query, "pagination" => @pagination}

      assert {:ok, {%Result{}, %Metadata{pagination: @pagination}}} =
               DnsAnalytics.query(client(200, body), 1010, page: 2)

      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 2})
      refute_received {:request, _request}
    end

    test "queryDnsAnalytics preserves empty groupings, omitted options, nullable dates, and zero metadata" do
      query = %{@query | "start_date" => nil, "end_date" => nil, "groupings" => nil, "page" => 0}
      pagination = %{@pagination | "current_page" => 0}
      body = %{"data" => @data, "query" => query, "pagination" => pagination}

      assert {:ok,
              {%Result{
                 query: %Query{start_date: nil, end_date: nil, groupings: nil, page: 0}
               }, %Metadata{pagination: ^pagination}}} =
               DnsAnalytics.list_page(client(200, body), 0)

      assert_request(:get, "/v2/0/dns_analytics")

      empty_query = %{@query | "groupings" => ""}
      empty_body = %{"data" => @data, "query" => empty_query, "pagination" => @pagination}

      assert {:ok, {%Result{query: %Query{groupings: ""}}, %Metadata{pagination: @pagination}}} =
               DnsAnalytics.list_page(client(200, empty_body), 1010, groupings: [])

      assert_request(:get, "/v2/1010/dns_analytics", %{"groupings" => ""})
    end

    test "queryDnsAnalytics validates paths, options, dates, grouping, sorting, and pagination" do
      request =
        client(200, %{"data" => @data, "query" => @query, "pagination" => @pagination})

      invalid_calls = [
        {"1010", []},
        {nil, []},
        {1010, [:invalid]},
        {1010, [{:name}]},
        {1010, [unknown: true]},
        {1010, [start_date: nil]},
        {1010, [start_date: "2026-02-30"]},
        {1010, [start_date: "2026-09-03", end_date: "2026-09-02"]},
        {1010, [start_date: "2026-09-01", end_date: "2026-10-02"]},
        {1010, [groupings: :date]},
        {1010, [groupings: [:volume]]},
        {1010, [groupings: [:date, "zone_name"]]},
        {1010, [sort: "volume:desc"]},
        {1010, [sort: [unknown: :asc]]},
        {1010, [sort: [volume: :sideways]]},
        {1010, [page: 0]},
        {1010, [per_page: 0]},
        {1010, [per_page: 10_001]}
      ]

      for {account_id, opts} <- invalid_calls do
        assert {:error, %Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 DnsAnalytics.list_page(request, account_id, opts)
      end

      refute_received {:request, _request}
    end

    test "queryDnsAnalytics preserves HTTP and transport failures" do
      for status <- [401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"start_date" => ["is unavailable"]}
        }

        assert {:error,
                %Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %Metadata{status: ^status}
                }} =
                 DnsAnalytics.list_page(client(status, body), 1010)

        assert_request(:get, "/v2/1010/dns_analytics")
        refute_received {:request, _request}
      end

      assert {:error, %Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               DnsAnalytics.list_page(transport_error_client(:timeout), 1010)
    end

    test "queryDnsAnalytics rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil, "query" => @query, "pagination" => @pagination},
        %{"data" => Map.delete(@data, "headers"), "query" => @query, "pagination" => @pagination},
        %{
          "data" => %{@data | "headers" => ["date", nil]},
          "query" => @query,
          "pagination" => @pagination
        },
        %{
          "data" => %{@data | "rows" => ["2026-09-02", 1200]},
          "query" => @query,
          "pagination" => @pagination
        },
        %{
          "data" => %{@data | "rows" => [["2026-09-02", 1.5]]},
          "query" => @query,
          "pagination" => @pagination
        },
        %{"data" => @data, "query" => Map.delete(@query, "sort"), "pagination" => @pagination},
        %{
          "data" => @data,
          "query" => %{@query | "start_date" => "bad"},
          "pagination" => @pagination
        },
        %{"data" => @data, "query" => %{@query | "sort" => nil}, "pagination" => @pagination}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %Metadata{status: 200}
                }} =
                 DnsAnalytics.list_page(client(200, body), 1010)

        assert_request(:get, "/v2/1010/dns_analytics")
        refute_received {:request, _request}
      end
    end

    test "valid data survives absent and malformed pagination with explicit metadata" do
      for pagination <- [
            :missing,
            nil,
            Map.delete(@pagination, "total_entries"),
            %{@pagination | "per_page" => -1},
            "invalid"
          ] do
        body = %{"data" => @data, "query" => @query}
        body = if pagination == :missing, do: body, else: Map.put(body, "pagination", pagination)

        assert {:ok, {%Result{}, %Metadata{status: 200, pagination: nil} = metadata}} =
                 DnsAnalytics.list_page(client(200, body), 1010)

        if pagination in [:missing, nil] do
          assert metadata.parse_errors == %{}
        else
          assert metadata.parse_errors == %{pagination: {:invalid_pagination, pagination}}
        end

        assert_request(:get, "/v2/1010/dns_analytics")
      end
    end
  end

  describe "list_all/3" do
    test "enumerates compatible pages from one while retaining first-page provenance" do
      first_query = %{@query | "page" => 1}
      second_query = %{@query | "page" => 2}
      first_page = %{@pagination | "current_page" => 1}
      second_data = %{@data | "rows" => [["2026-09-01", "second.test", 900]]}

      pages = %{
        1 => {200, %{"data" => @data, "query" => first_query, "pagination" => first_page}},
        2 => {200, %{"data" => second_data, "query" => second_query, "pagination" => @pagination}}
      }

      assert {:ok,
              {%Result{
                 headers: ["date", "zone_name", "volume"],
                 rows: [
                   ["2026-09-02", "example.test", 1200],
                   ["2026-09-01", "second.test", 900]
                 ],
                 query: %Query{page: 1, per_page: 1}
               }, %Metadata{} = metadata}} =
               DnsAnalytics.list_all(response_client(pages), 1010,
                 start_date: "2026-09-01",
                 end_date: "2026-09-02",
                 groupings: [:date, :zone_name],
                 sort: [date: :asc, zone_name: :desc],
                 per_page: 1
               )

      assert metadata.status == nil
      assert metadata.pagination == nil
      assert metadata.request_id == nil
      assert metadata.etag == nil
      assert metadata.rate_limit_remaining == 98
      assert Enum.map(metadata.pages, & &1.request_id) == ["analytics-page-1", "analytics-page-2"]
      assert Enum.map(metadata.pages, & &1.etag) == [~s(W/"page-1"), ~s(W/"page-2")]
      assert Enum.map(metadata.pages, & &1.pagination["current_page"]) == [1, 2]

      query = %{
        "start_date" => "2026-09-01",
        "end_date" => "2026-09-02",
        "groupings" => "date,zone_name",
        "sort" => "date:asc,zone_name:desc",
        "per_page" => 1
      }

      assert_request(:get, "/v2/1010/dns_analytics", Map.put(query, "page", 1))
      assert_request(:get, "/v2/1010/dns_analytics", Map.put(query, "page", 2))
      refute_received {:request, _request}
    end

    test "returns an empty typed result for an empty first page" do
      query = %{@query | "page" => 1}
      pagination = %{@pagination | "current_page" => 1, "total_entries" => 0, "total_pages" => 0}
      body = %{"data" => %{@data | "rows" => []}, "query" => query, "pagination" => pagination}

      assert {:ok,
              {%Result{rows: [], query: %Query{page: 1}},
               %Metadata{pages: [%Metadata{pagination: ^pagination}]}}} =
               DnsAnalytics.list_all(client(200, body), 1010)

      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 1})
      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request =
        client(200, %{"data" => @data, "query" => @query, "pagination" => @pagination})

      assert {:error, %Error{reason: {:invalid_option, :page}, metadata: nil}} =
               DnsAnalytics.list_all(request, 1010, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error, %Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 DnsAnalytics.list_all(request, 1010, opts)
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects pagination, header, and query mismatches" do
      first_query = %{@query | "page" => 1}
      first_page = %{@pagination | "current_page" => 1}
      first = %{"data" => @data, "query" => first_query, "pagination" => first_page}

      later_error = %{1 => {200, first}, 2 => {503, %{"message" => "unavailable"}}}

      assert {:error,
              %Error{
                reason: %{status: 503, response: %{"message" => "unavailable"}},
                metadata: %Metadata{
                  status: 503,
                  request_id: "analytics-page-2",
                  pages: [
                    %Metadata{status: 200, request_id: "analytics-page-1"},
                    %Metadata{status: 503, request_id: "analytics-page-2"}
                  ]
                }
              }} =
               DnsAnalytics.list_all(response_client(later_error), 1010)

      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 1})
      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 2})

      repeated = %{"data" => @data, "query" => first_query, "pagination" => first_page}

      assert {:error,
              %Error{
                reason: {:invalid_pagination, ^first_page},
                metadata: %Metadata{pages: [%Metadata{}, %Metadata{}]}
              }} =
               DnsAnalytics.list_all(
                 response_client(%{1 => {200, first}, 2 => {200, repeated}}),
                 1010
               )

      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 1})
      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 2})

      mismatches = [
        {:headers, %{@data | "headers" => ["zone_name", "date", "volume"]},
         %{@query | "page" => 2}},
        {:query, @data, %{@query | "page" => 2, "sort" => "volume:desc"}}
      ]

      for {kind, second_data, second_query} <- mismatches do
        second = %{"data" => second_data, "query" => second_query, "pagination" => @pagination}

        assert {:error,
                %Error{
                  reason: {:incompatible_page, ^kind},
                  metadata: %Metadata{pages: [%Metadata{}, %Metadata{}]}
                }} =
                 DnsAnalytics.list_all(
                   response_client(%{1 => {200, first}, 2 => {200, second}}),
                   1010
                 )

        assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 1})
        assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 2})
      end

      refute_received {:request, _request}
    end

    test "retains completed-page metadata when a later request has no HTTP response" do
      first = %{
        "data" => @data,
        "query" => %{@query | "page" => 1},
        "pagination" => %{@pagination | "current_page" => 1}
      }

      assert {:error,
              %Error{
                reason: %Req.TransportError{reason: :timeout},
                metadata: %Metadata{
                  status: nil,
                  request_id: nil,
                  etag: nil,
                  rate_limit_remaining: 99,
                  pages: [%Metadata{status: 200, request_id: "analytics-page-1"}]
                }
              }} =
               DnsAnalytics.list_all(
                 response_client(%{1 => {200, first}, 2 => {:error, :timeout}}),
                 1010
               )

      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 1})
      assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 2})
      refute_received {:request, _request}
    end

    test "rejects unusable pagination without losing its original value or HTTP metadata" do
      for pagination <- [nil, "invalid", Map.delete(@pagination, "total_entries")] do
        body = %{
          "data" => @data,
          "query" => %{@query | "page" => 1},
          "pagination" => pagination
        }

        assert {:error,
                %Error{
                  reason: {:invalid_pagination, ^pagination},
                  metadata: %Metadata{
                    status: 200,
                    request_id: "analytics-page-1",
                    pages: [%Metadata{request_id: "analytics-page-1"}]
                  }
                }} =
                 DnsAnalytics.list_all(response_client(%{1 => {200, body}}), 1010)

        assert_request(:get, "/v2/1010/dns_analytics", %{"page" => 1})
        refute_received {:request, _request}
      end
    end
  end

  defp response_client(pages) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request})

      page =
        request.url.query
        |> then(&URI.decode_query(&1 || ""))
        |> Map.get("page", "1")
        |> String.to_integer()

      case Map.fetch!(pages, page) do
        {:error, reason} ->
          {request, %Req.TransportError{reason: reason}}

        {status, body} ->
          {request,
           Req.Response.new(
             status: status,
             body: body,
             headers: [
               {"x-request-id", "analytics-page-#{page}"},
               {"etag", ~s(W/"page-#{page}")},
               {"x-ratelimit-remaining", Integer.to_string(100 - page)}
             ]
           )}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
