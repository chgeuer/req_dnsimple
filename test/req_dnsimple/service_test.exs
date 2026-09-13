defmodule ReqDnsimple.ServiceTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  describe "get/2" do
    test "getService retrieves one typed service with nullable nested fields" do
      body = %{
        "data" => %{
          "id" => 1,
          "name" => "Offline service",
          "sid" => "offline-service",
          "description" => "Offline example",
          "setup_description" => nil,
          "requires_setup" => true,
          "default_subdomain" => nil,
          "created_at" => "2026-09-01T10:00:00+02:00",
          "updated_at" => "2026-09-01T10:30:00+02:00",
          "settings" => [
            %{
              "name" => "example.test",
              "label" => "Offline example",
              "append" => nil,
              "description" => "Offline example",
              "example" => nil,
              "password" => true
            }
          ]
        }
      }

      assert {:ok,
              %ReqDnsimple.Service{
                id: 1,
                name: "Offline service",
                sid: "offline-service",
                description: "Offline example",
                setup_description: nil,
                requires_setup: true,
                default_subdomain: nil,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z],
                settings: [
                  %ReqDnsimple.Service.Setting{
                    name: "example.test",
                    label: "Offline example",
                    append: nil,
                    description: "Offline example",
                    example: nil,
                    password: true
                  }
                ]
              }} = ReqDnsimple.Service.get(client(200, body), "offline-service")

      assert_request(:get, "/v2/services/offline-service", %{}, nil)
      refute_received {:request, _request}
    end

    test "getService accepts integer, zero, and empty identifiers" do
      body = service_body()

      for service <- [12, 0, ""] do
        assert {:ok, %ReqDnsimple.Service{}} =
                 ReqDnsimple.Service.get(client(200, body), service)

        assert_request(:get, "/v2/services/#{service}", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getService rejects invalid identifiers before HTTP" do
      request = client(200, service_body())

      for service <- [nil, 1.5, [], %{}] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Service.get(request, service)
      end

      refute_received {:request, _request}
    end

    test "getService rejects malformed successful envelopes and payloads" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        put_in(service_body(), ["data", "created_at"], "not-a-timestamp"),
        put_in(service_body(), ["data", "settings"], [%{"name" => "incomplete"}]),
        put_in(service_body(), ["data", "requires_setup"], 0)
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Service.get(client(200, body), "offline-service")

        assert_request(:get, "/v2/services/offline-service", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getService preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"service" => ["was not found"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Service.get(client(status, body), "offline-service")

        assert_request(:get, "/v2/services/offline-service", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getService preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Service.get(transport_error_client(:timeout), "offline-service")
    end
  end

  describe "list_page_applied/4 and list_applied/4" do
    test "listDomainAppliedServices sends supported query options once and decodes typed data" do
      pagination = %{
        "current_page" => 2,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      data =
        Map.merge(service_data(), %{
          "requires_setup" => true,
          "default_subdomain" => nil,
          "created_at" => "2026-09-01T10:00:00+02:00",
          "settings" => [
            %{
              "name" => "example.test",
              "label" => "Offline example",
              "append" => nil,
              "description" => "Offline example",
              "example" => nil,
              "password" => true
            }
          ]
        })

      assert {:ok,
              {[
                 %ReqDnsimple.Service{
                   id: 1,
                   setup_description: nil,
                   requires_setup: true,
                   default_subdomain: nil,
                   created_at: ~U[2026-09-01 08:00:00Z],
                   settings: [
                     %ReqDnsimple.Service.Setting{
                       append: nil,
                       example: nil,
                       password: true
                     }
                   ]
                 }
               ], ^pagination}} =
               ReqDnsimple.Service.list_page_applied(
                 client(200, %{"data" => [data], "pagination" => pagination}),
                 1010,
                 "example.test",
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/services",
        %{"page" => 2, "per_page" => 1},
        nil
      )

      refute_received {:request, _request}
    end

    test "listDomainAppliedServices alias requests one empty page without materializing defaults" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 0,
        "total_pages" => 0
      }

      assert {:ok, {[], ^pagination}} =
               ReqDnsimple.Service.list_applied(
                 client(200, %{"data" => [], "pagination" => pagination}),
                 0,
                 0
               )

      assert_request(:get, "/v2/0/domains/0/services", %{}, nil)
      refute_received {:request, _request}
    end

    test "listDomainAppliedServices accepts empty domain identifiers" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      assert {:ok, {[%ReqDnsimple.Service{}], ^pagination}} =
               ReqDnsimple.Service.list_page_applied(
                 client(200, %{"data" => [service_data()], "pagination" => pagination}),
                 1010,
                 ""
               )

      assert_request(:get, "/v2/1010/domains//services", %{}, nil)
      refute_received {:request, _request}
    end

    test "listDomainAppliedServices rejects invalid paths and options before HTTP" do
      request = client(200, %{})

      invalid_calls = [
        {"1010", "example.test", []},
        {nil, "example.test", []},
        {1010, nil, []},
        {1010, 1.5, []},
        {1010, [], []},
        {1010, "example.test", [:invalid]},
        {1010, "example.test", [{:name}]},
        {1010, "example.test", [unknown: true]},
        {1010, "example.test", [page: 0]},
        {1010, "example.test", [per_page: 0]},
        {1010, "example.test", [per_page: 101]}
      ]

      for {account_id, domain, opts} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Service.list_page_applied(request, account_id, domain, opts)
      end

      refute_received {:request, _request}
    end

    test "listDomainAppliedServices preserves HTTP and transport failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"domain" => ["was not found"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Service.list_page_applied(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/services", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Service.list_page_applied(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end

    test "listDomainAppliedServices rejects malformed successful responses" do
      pagination = %{
        "current_page" => 1,
        "per_page" => 30,
        "total_entries" => 1,
        "total_pages" => 1
      }

      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => pagination},
        %{"data" => %{}, "pagination" => pagination},
        %{"data" => [Map.delete(service_data(), "settings")], "pagination" => pagination},
        %{"data" => [service_data()]},
        %{"data" => [service_data()], "pagination" => nil},
        %{
          "data" => [service_data()],
          "pagination" => Map.delete(pagination, "total_entries")
        },
        %{"data" => [service_data()], "pagination" => %{pagination | "per_page" => 0}}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Service.list_page_applied(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:get, "/v2/1010/domains/example.test/services", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  describe "list_all_applied/4" do
    test "enumerates from page one while preserving page size and server order" do
      second = Map.put(service_data(), "id", 2)

      pages = %{
        1 =>
          {[service_data()],
           %{
             "current_page" => 1,
             "per_page" => 1,
             "total_entries" => 2,
             "total_pages" => 2
           }},
        2 =>
          {[second],
           %{
             "current_page" => 2,
             "per_page" => 1,
             "total_entries" => 2,
             "total_pages" => 2
           }}
      }

      assert {:ok, [%ReqDnsimple.Service{id: 1}, %ReqDnsimple.Service{id: 2}]} =
               ReqDnsimple.Service.list_all_applied(
                 service_page_client(pages),
                 1010,
                 "example.test",
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/services",
        %{"page" => 1, "per_page" => 1}
      )

      assert_request(
        :get,
        "/v2/1010/domains/example.test/services",
        %{"page" => 2, "per_page" => 1}
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{})

      assert {:error, {:invalid_option, :page}} =
               ReqDnsimple.Service.list_all_applied(
                 request,
                 1010,
                 "example.test",
                 page: 2
               )

      for opts <- [[:invalid], [{:name}]] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Service.list_all_applied(
                   request,
                   1010,
                   "example.test",
                   opts
                 )
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page = %{
        "current_page" => 1,
        "per_page" => 1,
        "total_entries" => 2,
        "total_pages" => 2
      }

      http_client =
        service_response_client(fn
          1 -> {200, %{"data" => [service_data()], "pagination" => first_page}}
          2 -> {503, %{"message" => "unavailable"}}
        end)

      assert {:error, %{status: 503, response: %{"message" => "unavailable"}}} =
               ReqDnsimple.Service.list_all_applied(http_client, 1010, "example.test")

      assert_request(:get, "/v2/1010/domains/example.test/services", %{"page" => 1})
      assert_request(:get, "/v2/1010/domains/example.test/services", %{"page" => 2})

      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Service.list_all_applied(
                 service_response_client(fn
                   1 -> {200, %{"data" => [service_data()], "pagination" => first_page}}
                   2 -> {:error, :timeout}
                 end),
                 1010,
                 "example.test"
               )

      repeated = %{first_page | "current_page" => 1}

      assert {:error, {:invalid_pagination, ^repeated}} =
               ReqDnsimple.Service.list_all_applied(
                 service_response_client(fn _page ->
                   {200, %{"data" => [service_data()], "pagination" => repeated}}
                 end),
                 1010,
                 "example.test"
               )
    end
  end

  describe "apply/4 and apply/5" do
    test "applyServiceToDomain sends one request with string-keyed settings and returns :ok" do
      assert :ok =
               ReqDnsimple.Service.apply(
                 client(204, ""),
                 1010,
                 "example.test",
                 "offline-service",
                 settings: %{
                   "app" => "fake-offline-app",
                   "enabled" => false,
                   "priority" => 0,
                   "aliases" => [],
                   "metadata" => %{},
                   "note" => ""
                 }
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        %{
          settings: %{
            "app" => "fake-offline-app",
            "enabled" => false,
            "priority" => 0,
            "aliases" => [],
            "metadata" => %{},
            "note" => ""
          }
        }
      )

      refute_received {:request, _request}
    end

    test "applyServiceToDomain distinguishes omitted settings from an explicit empty object" do
      assert :ok =
               ReqDnsimple.Service.apply(
                 client(204, nil),
                 1010,
                 "example.test",
                 "offline-service"
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        nil
      )

      refute_received {:request, _request}

      assert :ok =
               ReqDnsimple.Service.apply(
                 client(204, nil),
                 1010,
                 "example.test",
                 "offline-service",
                 settings: %{}
               )

      assert_request(
        :post,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        %{settings: %{}}
      )

      refute_received {:request, _request}
    end

    test "applyServiceToDomain accepts integer, zero, and empty identifiers" do
      for {account_id, domain, service} <- [{0, 0, 0}, {1010, "", ""}] do
        assert :ok =
                 ReqDnsimple.Service.apply(
                   client(204, nil),
                   account_id,
                   domain,
                   service
                 )

        assert_request(
          :post,
          "/v2/#{account_id}/domains/#{domain}/services/#{service}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyServiceToDomain rejects invalid paths and attributes before HTTP" do
      request = client(204, nil)

      invalid_calls = [
        {"1010", "example.test", "offline-service", []},
        {nil, "example.test", "offline-service", []},
        {1010, nil, "offline-service", []},
        {1010, 1.5, "offline-service", []},
        {1010, "example.test", nil, []},
        {1010, "example.test", 1.5, []},
        {1010, "example.test", "offline-service", [settings: nil]},
        {1010, "example.test", "offline-service", [settings: []]},
        {1010, "example.test", "offline-service", [settings: %{app: "fake"}]},
        {1010, "example.test", "offline-service", [unknown: true]},
        {1010, "example.test", "offline-service", [:invalid]},
        {1010, "example.test", "offline-service", [{:name}]},
        {1010, "example.test", "offline-service", %{settings: %{}}}
      ]

      for {account_id, domain, service, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Service.apply(request, account_id, domain, service, attrs)
      end

      refute_received {:request, _request}
    end

    test "applyServiceToDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"settings" => ["are invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Service.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyServiceToDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Service.apply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :post,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "applyServiceToDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Service.apply(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 "offline-service"
               )
    end
  end

  describe "unapply/4" do
    test "unapplyServiceFromDomain sends one bodyless request and returns :ok" do
      assert :ok =
               ReqDnsimple.Service.unapply(
                 client(204, ""),
                 1010,
                 "example.test",
                 "offline-service"
               )

      assert_request(
        :delete,
        "/v2/1010/domains/example.test/services/offline-service",
        %{},
        nil
      )

      refute_received {:request, _request}
    end

    test "unapplyServiceFromDomain accepts integer, zero, and empty identifiers" do
      for {account_id, domain, service} <- [{0, 0, 0}, {1010, "", ""}] do
        assert :ok =
                 ReqDnsimple.Service.unapply(
                   client(204, nil),
                   account_id,
                   domain,
                   service
                 )

        assert_request(
          :delete,
          "/v2/#{account_id}/domains/#{domain}/services/#{service}",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "unapplyServiceFromDomain rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, domain, service} <- [
            {"1010", "example.test", "offline-service"},
            {nil, "example.test", "offline-service"},
            {1010, nil, "offline-service"},
            {1010, 1.5, "offline-service"},
            {1010, "example.test", nil},
            {1010, "example.test", 1.5}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Service.unapply(request, account_id, domain, service)
      end

      refute_received {:request, _request}
    end

    test "unapplyServiceFromDomain preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"service" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Service.unapply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :delete,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "unapplyServiceFromDomain rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Service.unapply(
                   client(status, body),
                   1010,
                   "example.test",
                   "offline-service"
                 )

        assert_request(
          :delete,
          "/v2/1010/domains/example.test/services/offline-service",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "unapplyServiceFromDomain preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Service.unapply(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 "offline-service"
               )
    end
  end

  defp service_body do
    %{"data" => service_data()}
  end

  defp service_data do
    %{
      "id" => 1,
      "name" => "Offline service",
      "sid" => "offline-service",
      "description" => "Offline example",
      "setup_description" => nil,
      "requires_setup" => false,
      "default_subdomain" => "",
      "created_at" => "2026-09-01T10:00:00Z",
      "updated_at" => "2026-09-01T10:30:00Z",
      "settings" => []
    }
  end

  defp service_page_client(pages) do
    service_response_client(fn page ->
      {data, pagination} = Map.fetch!(pages, page)
      {200, %{"data" => data, "pagination" => pagination}}
    end)
  end

  defp service_response_client(response_for_page) do
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
          {request, %Req.Response{status: status, body: body}}
      end
    end

    ReqDnsimple.new_client("dnsimple_u_fake-token")
    |> Req.merge(adapter: adapter, retry: false)
  end
end
