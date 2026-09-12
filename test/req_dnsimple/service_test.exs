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
    %{
      "data" => %{
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
    }
  end
end
