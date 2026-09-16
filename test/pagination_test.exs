defmodule ReqDnsimple.PaginationTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  alias ReqDnsimple.{Error, Metadata}

  @pagination %{
    "current_page" => 1,
    "per_page" => 2,
    "total_entries" => 1,
    "total_pages" => 1
  }

  test "list_page returns typed items with nested pagination metadata for every resource" do
    cases = [
      {&ReqDnsimple.Zone.list_page(&1, 1010, name_like: "example"),
       %{"id" => 1, "name" => "example.com"}, ReqDnsimple.Zone, "/v2/1010/zones",
       %{"name_like" => "example"}},
      {&ReqDnsimple.Contact.list_page(&1, 1010, sort: [:id]), %{"id" => 2}, ReqDnsimple.Contact,
       "/v2/1010/contacts", %{"sort" => "id:asc"}},
      {&ReqDnsimple.BillingCharge.list_page(&1, 1010, per_page: 2),
       %{"reference" => "INV-1", "items" => []}, ReqDnsimple.BillingCharge,
       "/v2/1010/billing/charges", %{"per_page" => 2}},
      {&ReqDnsimple.ZoneRecord.list_page(&1, 1010, "example.com", type: "A"), %{"id" => 3},
       ReqDnsimple.ZoneRecord, "/v2/1010/zones/example.com/records", %{"type" => "A"}}
    ]

    for {operation, item, module, path, query} <- cases do
      assert {:ok, {[typed_item], %Metadata{status: 200, pagination: @pagination}}} =
               operation.(client(200, %{"data" => [item], "pagination" => @pagination}))

      assert typed_item.__struct__ == module
      assert_request(:get, path, query)
    end
  end

  test "list functions consistently retain pagination in response metadata" do
    zone = %{"id" => 1}
    contact = %{"id" => 2}
    charge = %{"reference" => "INV-1", "items" => []}
    record = %{"id" => 3}

    assert {:ok, {[%ReqDnsimple.Zone{id: 1}], %Metadata{pagination: @pagination}}} =
             ReqDnsimple.Zone.list(page_client(%{1 => {[zone], @pagination}}), 1010)

    assert {:ok, {[%ReqDnsimple.Contact{id: 2}], %Metadata{pagination: @pagination}}} =
             ReqDnsimple.Contact.list(page_client(%{1 => {[contact], @pagination}}), 1010)

    assert {:ok,
            {[%ReqDnsimple.BillingCharge{reference: "INV-1"}], %Metadata{pagination: @pagination}}} =
             ReqDnsimple.BillingCharge.list(page_client(%{1 => {[charge], @pagination}}), 1010)

    assert {:ok, {[%ReqDnsimple.ZoneRecord{id: 3}], %Metadata{pagination: @pagination}}} =
             ReqDnsimple.ZoneRecord.list(
               page_client(%{1 => {[record], @pagination}}),
               1010,
               "example.com"
             )
  end

  test "list_all starts at page one and preserves filters, sorting, and page size" do
    pages = %{
      1 =>
        {[%{"id" => 1, "name" => "first.example"}],
         %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}},
      2 =>
        {[%{"id" => 2, "name" => "second.example"}],
         %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}}
    }

    assert {:ok, {[%ReqDnsimple.Zone{id: 1}, %ReqDnsimple.Zone{id: 2}], %Metadata{} = metadata}} =
             ReqDnsimple.Zone.list_all(page_client(pages), 1010,
               name_like: "example",
               sort: [name: :desc],
               per_page: 2
             )

    assert metadata.status == nil
    assert metadata.pagination == nil
    assert metadata.request_id == nil
    assert metadata.etag == nil
    assert metadata.rate_limit == 2400
    assert metadata.rate_limit_remaining == 2398
    assert metadata.rate_limit_reset == 1_790_000_000
    assert Enum.map(metadata.pages, & &1.request_id) == ["page-1", "page-2"]
    assert Enum.map(metadata.pages, & &1.etag) == [~s("page-1"), ~s("page-2")]
    assert Enum.map(metadata.pages, & &1.pagination["current_page"]) == [1, 2]

    expected_query = %{"name_like" => "example", "sort" => "name:desc", "per_page" => 2}
    assert_request(:get, "/v2/1010/zones", Map.put(expected_query, "page", 1))
    assert_request(:get, "/v2/1010/zones", Map.put(expected_query, "page", 2))
  end

  test "list_all handles empty and one-page collections for every resource" do
    empty_page = %{@pagination | "total_entries" => 0, "total_pages" => 0}

    assert {:ok, {[], %Metadata{status: nil, pages: [%Metadata{pagination: ^empty_page}]}}} =
             ReqDnsimple.Zone.list_all(page_client(%{1 => {[], empty_page}}), 1010)

    assert {:ok, {[%ReqDnsimple.Contact{id: 2}], %Metadata{pages: [%Metadata{}]}}} =
             ReqDnsimple.Contact.list_all(
               page_client(%{1 => {[%{"id" => 2}], @pagination}}),
               1010
             )

    assert {:ok,
            {[%ReqDnsimple.BillingCharge{reference: "INV-1"}], %Metadata{pages: [%Metadata{}]}}} =
             ReqDnsimple.BillingCharge.list_all(
               page_client(%{1 => {[%{"reference" => "INV-1", "items" => []}], @pagination}}),
               1010
             )

    assert {:ok, {[%ReqDnsimple.ZoneRecord{id: 3}], %Metadata{pages: [%Metadata{}]}}} =
             ReqDnsimple.ZoneRecord.list_all(
               page_client(%{1 => {[%{"id" => 3}], @pagination}}),
               1010,
               "example.com"
             )
  end

  test "list_all rejects an explicit page and invalid page sizes without requesting" do
    req = ReqDnsimple.new_client("dnsimple_u_fake-token")

    assert {:error, %Error{reason: {:invalid_option, :page}, metadata: nil}} =
             ReqDnsimple.Zone.list_all(req, 1010, page: 2)

    assert {:error, %Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
             ReqDnsimple.Zone.list_all(req, 1010, per_page: 0)

    refute_received {:request, _request}
  end

  test "list_all returns middle-page HTTP and transport errors without partial success" do
    first_page =
      %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

    http_client =
      response_client(fn
        1 -> {200, %{"data" => [%{"id" => 1}], "pagination" => first_page}}
        2 -> {503, %{"message" => "unavailable"}}
      end)

    assert {:error,
            %Error{
              reason: %{status: 503, response: %{"message" => "unavailable"}},
              metadata: %Metadata{status: 503, request_id: "page-2"} = http_metadata
            }} =
             ReqDnsimple.Zone.list_all(http_client, 1010)

    assert Enum.map(http_metadata.pages, & &1.status) == [200, 503]
    assert Enum.map(http_metadata.pages, & &1.request_id) == ["page-1", "page-2"]

    transport_client =
      response_client(fn
        1 -> {200, %{"data" => [%{"id" => 1}], "pagination" => first_page}}
        2 -> {:error, :econnrefused}
      end)

    assert {:error,
            %Error{
              reason: %Req.TransportError{reason: :econnrefused},
              metadata: %Metadata{
                status: nil,
                request_id: nil,
                etag: nil,
                pages: [%Metadata{request_id: "page-1"}]
              }
            }} =
             ReqDnsimple.Zone.list_all(transport_client, 1010)
  end

  test "list_all rejects malformed and non-progressing pagination" do
    malformed = %{"current_page" => 1, "total_pages" => 2}

    assert {:error,
            %Error{
              reason: {:invalid_pagination, ^malformed},
              metadata: %Metadata{status: 200, pages: [%Metadata{}]}
            }} =
             ReqDnsimple.Zone.list_all(page_client(%{1 => {[%{"id" => 1}], malformed}}), 1010)

    assert_request(:get, "/v2/1010/zones", %{"page" => 1})

    repeated =
      %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

    client =
      response_client(fn _page ->
        {200, %{"data" => [%{"id" => 1}], "pagination" => repeated}}
      end)

    assert {:error,
            %Error{
              reason: {:invalid_pagination, ^repeated},
              metadata: %Metadata{pages: [%Metadata{}, %Metadata{}]}
            }} =
             ReqDnsimple.Zone.list_all(client, 1010)

    assert_request(:get, "/v2/1010/zones", %{"page" => 1})
    assert_request(:get, "/v2/1010/zones", %{"page" => 2})
    refute_received {:request, _request}
  end

  defp page_client(pages) do
    response_client(fn page ->
      {data, pagination} = Map.fetch!(pages, page)
      {200, %{"data" => data, "pagination" => pagination}}
    end)
  end

  defp response_client(response_for_page) do
    test_pid = self()

    adapter = fn request ->
      send(test_pid, {:request, request})

      page =
        request.url.query
        |> then(&URI.decode_query(&1 || ""))
        |> Map.get("page", "1")
        |> String.to_integer()

      case response_for_page.(page) do
        {:error, reason} ->
          {request, %Req.TransportError{reason: reason}}

        {status, body} ->
          {request,
           Req.Response.new(
             status: status,
             body: body,
             headers: [
               {"x-request-id", "page-#{page}"},
               {"etag", ~s("page-#{page}")},
               {"x-ratelimit-limit", "2400"},
               {"x-ratelimit-remaining", Integer.to_string(2400 - page)},
               {"x-ratelimit-reset", "1790000000"}
             ]
           )}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
