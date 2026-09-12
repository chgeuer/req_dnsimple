defmodule ReqDnsimple.PrimaryServerTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @primary_server_data %{
    "id" => 1,
    "account_id" => 1010,
    "name" => "Offline primary",
    "ip" => "192.0.2.1",
    "port" => 5353,
    "linked_secondary_zones" => [],
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  describe "get/3" do
    test "getPrimaryServer requests one unlinked server and returns a typed response" do
      assert {:ok,
              %ReqDnsimple.PrimaryServer{
                id: 1,
                account_id: 1010,
                name: "Offline primary",
                ip: "192.0.2.1",
                port: 5353,
                linked_secondary_zones: [],
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.PrimaryServer.get(
                 client(200, %{"data" => @primary_server_data}),
                 1010,
                 1
               )

      assert_request(:get, "/v2/1010/secondary_dns/primaries/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getPrimaryServer preserves ordered linked secondary-zone names" do
      data =
        Map.put(
          @primary_server_data,
          "linked_secondary_zones",
          ["secondary.example", "secondary.example.net"]
        )

      assert {:ok,
              %ReqDnsimple.PrimaryServer{
                linked_secondary_zones: [
                  "secondary.example",
                  "secondary.example.net"
                ]
              }} =
               ReqDnsimple.PrimaryServer.get(client(200, %{"data" => data}), 1010, 1)

      assert_request(:get, "/v2/1010/secondary_dns/primaries/1")
      refute_received {:request, _request}
    end

    test "getPrimaryServer rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @primary_server_data})

      for {account_id, primary_server_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, "1"},
            {1010, nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.PrimaryServer.get(request, account_id, primary_server_id)
      end

      refute_received {:request, _request}
    end

    test "getPrimaryServer preserves explicit zero identifiers" do
      data = Map.merge(@primary_server_data, %{"id" => 0, "account_id" => 0})

      assert {:ok, %ReqDnsimple.PrimaryServer{id: 0, account_id: 0}} =
               ReqDnsimple.PrimaryServer.get(client(200, %{"data" => data}), 0, 0)

      assert_request(:get, "/v2/0/secondary_dns/primaries/0")
    end

    test "getPrimaryServer preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"primaryserver" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.PrimaryServer.get(client(status, body), 1010, 1)

        assert_request(:get, "/v2/1010/secondary_dns/primaries/1")
        refute_received {:request, _request}
      end
    end

    test "getPrimaryServer returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@primary_server_data, "port")},
        %{"data" => Map.put(@primary_server_data, "port", "5353")},
        %{"data" => Map.put(@primary_server_data, "linked_secondary_zones", [nil])},
        %{"data" => Map.put(@primary_server_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.PrimaryServer.get(client(200, body), 1010, 1)

        assert_request(:get, "/v2/1010/secondary_dns/primaries/1")
        refute_received {:request, _request}
      end
    end

    test "getPrimaryServer preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.PrimaryServer.get(transport_error_client(:timeout), 1010, 1)
    end
  end

  describe "delete/3" do
    test "removePrimaryServer sends one bodyless request and returns :ok" do
      assert :ok = ReqDnsimple.PrimaryServer.delete(client(204, ""), 1010, 1)

      assert_request(:delete, "/v2/1010/secondary_dns/primaries/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "removePrimaryServer rejects invalid path parameters before HTTP" do
      request = client(204, "")

      for {account_id, primary_server_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, "1"},
            {1010, nil}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.PrimaryServer.delete(request, account_id, primary_server_id)
      end

      refute_received {:request, _request}
    end

    test "removePrimaryServer preserves explicit zero identifiers" do
      assert :ok = ReqDnsimple.PrimaryServer.delete(client(204, nil), 0, 0)

      assert_request(:delete, "/v2/0/secondary_dns/primaries/0", %{}, nil)
    end

    test "removePrimaryServer preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"primaryserver" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.PrimaryServer.delete(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/secondary_dns/primaries/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "removePrimaryServer rejects non-204 successful responses" do
      for {status, body} <- [{200, %{}}, {200, nil}, {201, %{"data" => %{}}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.PrimaryServer.delete(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/secondary_dns/primaries/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "removePrimaryServer preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.PrimaryServer.delete(transport_error_client(:timeout), 1010, 1)
    end
  end
end
