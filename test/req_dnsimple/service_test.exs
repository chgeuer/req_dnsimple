defmodule ReqDnsimple.ServiceTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

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
end
