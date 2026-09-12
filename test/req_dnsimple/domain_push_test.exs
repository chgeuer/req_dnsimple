defmodule ReqDnsimple.DomainPushTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @push_data %{
    "id" => 1,
    "domain_id" => 100,
    "contact_id" => nil,
    "account_id" => 2020,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00",
    "accepted_at" => nil
  }

  @pagination %{
    "current_page" => 1,
    "per_page" => 1,
    "total_entries" => 1,
    "total_pages" => 1
  }

  describe "initiate/4" do
    test "initiateDomainPush sends one request and returns the typed pending push" do
      assert {:ok,
              %ReqDnsimple.DomainPush{
                id: 1,
                domain_id: 100,
                contact_id: nil,
                account_id: 2020,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z],
                accepted_at: nil
              }} =
               ReqDnsimple.DomainPush.initiate(
                 client(201, %{"data" => @push_data}),
                 1010,
                 "example.test",
                 new_account_identifier: "00000000-0000-7000-8000-000000000002"
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/pushes",
        %{},
        %{new_account_identifier: "00000000-0000-7000-8000-000000000002"}
      )

      refute_received {:request, _request}
    end

    test "initiateDomainPush supports the deprecated email target and numeric domain IDs" do
      assert {:ok, %ReqDnsimple.DomainPush{}} =
               ReqDnsimple.DomainPush.initiate(
                 client(201, %{"data" => @push_data}),
                 0,
                 0,
                 new_account_email: ""
               )

      assert_request(
        :post,
        "/v2/0/domains/0/pushes",
        %{},
        %{new_account_email: ""}
      )

      refute_received {:request, _request}
    end

    test "initiateDomainPush rejects invalid paths and attributes before HTTP" do
      request = client(201, %{"data" => @push_data})

      invalid_arguments = [
        {"1010", "example.test", [new_account_identifier: "target"]},
        {nil, "example.test", [new_account_identifier: "target"]},
        {1010, nil, [new_account_identifier: "target"]},
        {1010, false, [new_account_identifier: "target"]},
        {1010, [], [new_account_identifier: "target"]},
        {1010, %{}, [new_account_identifier: "target"]},
        {1010, "example.test", []},
        {1010, "example.test", [new_account_identifier: nil]},
        {1010, "example.test", [new_account_identifier: 0]},
        {1010, "example.test", [new_account_identifier: false]},
        {1010, "example.test", [new_account_identifier: []]},
        {1010, "example.test", [new_account_identifier: %{}]},
        {1010, "example.test", [new_account_email: nil]},
        {1010, "example.test", [new_account_email: 0]},
        {1010, "example.test",
         [new_account_identifier: "target", new_account_email: "target@example.test"]},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", [:invalid]},
        {1010, "example.test", [{:name}]},
        {1010, "example.test", %{new_account_identifier: "target"}}
      ]

      for {account_id, domain, attrs} <- invalid_arguments do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DomainPush.initiate(request, account_id, domain, attrs)
      end

      refute_received {:request, _request}
    end

    test "initiateDomainPush preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"new_account_identifier" => ["is not eligible"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.initiate(
                   client(status, body),
                   1010,
                   "example.test",
                   new_account_identifier: "target"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/pushes",
          %{},
          %{new_account_identifier: "target"}
        )

        refute_received {:request, _request}
      end
    end

    test "initiateDomainPush rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@push_data, "id")},
        %{"data" => %{@push_data | "contact_id" => "11"}},
        %{"data" => %{@push_data | "accepted_at" => "not-a-date"}}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 201, response: ^body}} =
                 ReqDnsimple.DomainPush.initiate(
                   client(201, body),
                   1010,
                   "example.test",
                   new_account_identifier: "target"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/pushes",
          %{},
          %{new_account_identifier: "target"}
        )

        refute_received {:request, _request}
      end
    end

    test "initiateDomainPush preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.DomainPush.initiate(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 new_account_identifier: "target"
               )
    end
  end

  describe "list_page/3 and list/3" do
    test "listPushes sends pagination once and returns typed pending pushes" do
      pagination = %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}

      assert {:ok,
              {[
                 %ReqDnsimple.DomainPush{
                   id: 1,
                   domain_id: 100,
                   contact_id: nil,
                   account_id: 2020,
                   created_at: ~U[2026-09-01 08:00:00Z],
                   updated_at: ~U[2026-09-01 08:30:00Z],
                   accepted_at: nil
                 }
               ], ^pagination}} =
               ReqDnsimple.DomainPush.list_page(
                 client(200, %{"data" => [@push_data], "pagination" => pagination}),
                 2020,
                 page: 2,
                 per_page: 1
               )

      assert_request(:get, "/v2/2020/pushes", %{"page" => 2, "per_page" => 1}, nil)
      refute_received {:request, _request}
    end

    test "listPushes alias returns an empty page and parses nullable timestamps" do
      accepted = Map.put(@push_data, "accepted_at", "2026-09-02T10:00:00+02:00")

      assert {:ok,
              {[%ReqDnsimple.DomainPush{accepted_at: ~U[2026-09-02 08:00:00Z]}], @pagination}} =
               ReqDnsimple.DomainPush.list(
                 client(200, %{"data" => [accepted], "pagination" => @pagination}),
                 0
               )

      assert_request(:get, "/v2/0/pushes", %{}, nil)
      refute_received {:request, _request}

      empty_pagination = %{@pagination | "total_entries" => 0, "total_pages" => 0}

      assert {:ok, {[], ^empty_pagination}} =
               ReqDnsimple.DomainPush.list_page(
                 client(200, %{"data" => [], "pagination" => empty_pagination}),
                 2020
               )
    end

    test "listPushes rejects invalid paths and options before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      for {account_id, opts} <- [
            {"2020", []},
            {nil, []},
            {2020, [:invalid]},
            {2020, [{:name}]},
            {2020, [unknown: true]},
            {2020, [page: 0]},
            {2020, [per_page: 0]},
            {2020, [per_page: 101]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DomainPush.list_page(request, account_id, opts)
      end

      refute_received {:request, _request}
    end

    test "listPushes preserves HTTP and transport failures" do
      for status <- [401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"account" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.list_page(client(status, body), 2020)

        assert_request(:get, "/v2/2020/pushes", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.DomainPush.list_page(transport_error_client(:timeout), 2020)
    end

    test "listPushes rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => @pagination},
        %{"data" => [Map.delete(@push_data, "contact_id")], "pagination" => @pagination},
        %{"data" => [Map.delete(@push_data, "accepted_at")], "pagination" => @pagination},
        %{"data" => [Map.put(@push_data, "contact_id", "11")], "pagination" => @pagination},
        %{"data" => [Map.put(@push_data, "created_at", "invalid")], "pagination" => @pagination},
        %{"data" => [@push_data]},
        %{"data" => [@push_data], "pagination" => nil},
        %{"data" => [@push_data], "pagination" => Map.delete(@pagination, "total_entries")},
        %{"data" => [@push_data], "pagination" => %{@pagination | "per_page" => 0}}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.DomainPush.list_page(client(200, body), 2020)

        assert_request(:get, "/v2/2020/pushes", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  describe "list_all/3" do
    test "returns empty and one-page collections without extra requests" do
      empty_pagination = %{@pagination | "total_entries" => 0, "total_pages" => 0}

      assert {:ok, []} =
               ReqDnsimple.DomainPush.list_all(
                 client(200, %{"data" => [], "pagination" => empty_pagination}),
                 2020
               )

      assert_request(:get, "/v2/2020/pushes", %{"page" => 1})
      refute_received {:request, _request}

      assert {:ok, [%ReqDnsimple.DomainPush{id: 1}]} =
               ReqDnsimple.DomainPush.list_all(
                 client(200, %{"data" => [@push_data], "pagination" => @pagination}),
                 2020
               )

      assert_request(:get, "/v2/2020/pushes", %{"page" => 1})
      refute_received {:request, _request}
    end

    test "enumerates from page one in server order while preserving per_page" do
      second = Map.merge(@push_data, %{"id" => 2, "domain_id" => 200})

      pages = %{
        1 =>
          {[@push_data],
           %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}},
        2 =>
          {[second],
           %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}}
      }

      assert {:ok,
              [
                %ReqDnsimple.DomainPush{id: 1, domain_id: 100},
                %ReqDnsimple.DomainPush{id: 2, domain_id: 200}
              ]} = ReqDnsimple.DomainPush.list_all(page_client(pages), 2020, per_page: 1)

      assert_request(:get, "/v2/2020/pushes", %{"page" => 1, "per_page" => 1})
      assert_request(:get, "/v2/2020/pushes", %{"page" => 2, "per_page" => 1})
      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      assert {:error, {:invalid_option, :page}} =
               ReqDnsimple.DomainPush.list_all(request, 2020, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DomainPush.list_all(request, 2020, opts)
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page =
        %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error, %{status: 503, response: %{"message" => "unavailable"}}} =
               ReqDnsimple.DomainPush.list_all(
                 response_client(fn
                   1 -> {200, %{"data" => [@push_data], "pagination" => first_page}}
                   2 -> {503, %{"message" => "unavailable"}}
                 end),
                 2020
               )

      assert_request(:get, "/v2/2020/pushes", %{"page" => 1})
      assert_request(:get, "/v2/2020/pushes", %{"page" => 2})

      repeated = %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error, {:invalid_pagination, ^repeated}} =
               ReqDnsimple.DomainPush.list_all(
                 response_client(fn _page ->
                   {200, %{"data" => [@push_data], "pagination" => repeated}}
                 end),
                 2020
               )

      assert_request(:get, "/v2/2020/pushes", %{"page" => 1})
      assert_request(:get, "/v2/2020/pushes", %{"page" => 2})
      refute_received {:request, _request}
    end
  end

  describe "accept/4" do
    test "acceptPush sends one request with the selected contact and returns :ok" do
      assert :ok =
               ReqDnsimple.DomainPush.accept(
                 client(204, ""),
                 2020,
                 1,
                 contact_id: 11
               )

      assert_request(:post, "/v2/2020/pushes/1", %{}, %{contact_id: 11})
      refute_received {:request, _request}
    end

    test "acceptPush preserves explicit zero identifiers" do
      assert :ok =
               ReqDnsimple.DomainPush.accept(
                 client(204, nil),
                 0,
                 0,
                 contact_id: 0
               )

      assert_request(:post, "/v2/0/pushes/0", %{}, %{contact_id: 0})
      refute_received {:request, _request}
    end

    test "acceptPush rejects invalid path parameters and attributes before HTTP" do
      request = client(204, "")

      invalid_arguments = [
        {"2020", 1, [contact_id: 11]},
        {nil, 1, [contact_id: 11]},
        {2020, "1", [contact_id: 11]},
        {2020, nil, [contact_id: 11]},
        {2020, 1, []},
        {2020, 1, [contact_id: nil]},
        {2020, 1, [contact_id: "11"]},
        {2020, 1, [contact_id: false]},
        {2020, 1, [contact_id: ""]},
        {2020, 1, [contact_id: []]},
        {2020, 1, [contact_id: %{}]},
        {2020, 1, [contact_id: 11, unknown: true]},
        {2020, 1, [:invalid]},
        {2020, 1, [{:name}]},
        {2020, 1, %{contact_id: 11}}
      ]

      for {account_id, push_id, attrs} <- invalid_arguments do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DomainPush.accept(request, account_id, push_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "acceptPush preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"contact_id" => ["is not eligible"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.accept(
                   client(status, body),
                   2020,
                   1,
                   contact_id: 11
                 )

        assert_request(:post, "/v2/2020/pushes/1", %{}, %{contact_id: 11})
        refute_received {:request, _request}
      end
    end

    test "acceptPush rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.accept(
                   client(status, body),
                   2020,
                   1,
                   contact_id: 11
                 )

        assert_request(:post, "/v2/2020/pushes/1", %{}, %{contact_id: 11})
        refute_received {:request, _request}
      end
    end

    test "acceptPush preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.DomainPush.accept(
                 transport_error_client(:timeout),
                 2020,
                 1,
                 contact_id: 11
               )
    end
  end

  describe "reject/3" do
    test "rejectPush sends one bodyless request and returns :ok" do
      assert :ok = ReqDnsimple.DomainPush.reject(client(204, ""), 2020, 1)

      assert_request(:delete, "/v2/2020/pushes/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "rejectPush preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.DomainPush.reject(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/pushes/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "rejectPush rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, push_id} <- [
            {"2020", 1},
            {nil, 1},
            {2020, "1"},
            {2020, nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.DomainPush.reject(request, account_id, push_id)
      end

      refute_received {:request, _request}
    end

    test "rejectPush preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"push" => ["cannot be rejected"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.reject(client(status, body), 2020, 1)

        assert_request(:delete, "/v2/2020/pushes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "rejectPush rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.DomainPush.reject(client(status, body), 2020, 1)

        assert_request(:delete, "/v2/2020/pushes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "rejectPush preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.DomainPush.reject(transport_error_client(:timeout), 2020, 1)
    end
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
      page = request.url.query |> URI.decode_query() |> Map.fetch!("page") |> String.to_integer()
      {status, body} = response_for_page.(page)
      {request, %Req.Response{status: status, body: body}}
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
