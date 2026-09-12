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

  describe "create/3" do
    test "createPrimaryServer sends every supplied field once and returns a typed response" do
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
               ReqDnsimple.PrimaryServer.create(
                 client(201, %{"data" => @primary_server_data}),
                 1010,
                 name: "Offline primary",
                 ip: "192.0.2.1",
                 port: 5353
               )

      assert_request(
        :post,
        "/v2/1010/secondary_dns/primaries",
        %{},
        %{"name" => "Offline primary", "ip" => "192.0.2.1", "port" => 5353}
      )

      refute_received {:request, _request}
    end

    test "createPrimaryServer omits an absent port and preserves zero and empty strings" do
      request = client(201, %{"data" => @primary_server_data})

      assert {:ok, %ReqDnsimple.PrimaryServer{}} =
               ReqDnsimple.PrimaryServer.create(request, 1010, name: "", ip: "")

      assert_request(
        :post,
        "/v2/1010/secondary_dns/primaries",
        %{},
        %{"name" => "", "ip" => ""}
      )

      zero_port_data = Map.put(@primary_server_data, "port", 0)

      assert {:ok, %ReqDnsimple.PrimaryServer{port: 0}} =
               ReqDnsimple.PrimaryServer.create(
                 client(201, %{"data" => zero_port_data}),
                 0,
                 name: "Zero port",
                 ip: "192.0.2.2",
                 port: 0
               )

      assert_request(
        :post,
        "/v2/0/secondary_dns/primaries",
        %{},
        %{"name" => "Zero port", "ip" => "192.0.2.2", "port" => 0}
      )
    end

    test "createPrimaryServer rejects invalid attributes before HTTP" do
      request = client(201, %{"data" => @primary_server_data})

      for {account_id, attrs} <- [
            {"1010", [name: "Primary", ip: "192.0.2.1"]},
            {nil, [name: "Primary", ip: "192.0.2.1"]},
            {1010, [:invalid]},
            {1010, [{:name}]},
            {1010, []},
            {1010, [name: "Primary"]},
            {1010, [ip: "192.0.2.1"]},
            {1010, [name: nil, ip: "192.0.2.1"]},
            {1010, [name: "Primary", ip: nil]},
            {1010, [name: false, ip: "192.0.2.1"]},
            {1010, [name: "Primary", ip: "192.0.2.1", port: nil]},
            {1010, [name: "Primary", ip: "192.0.2.1", port: "5353"]},
            {1010, [name: "Primary", ip: "192.0.2.1", port: []]},
            {1010, [name: "Primary", ip: "192.0.2.1", port: %{}]},
            {1010, [name: "Primary", ip: "192.0.2.1", unknown: true]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.PrimaryServer.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createPrimaryServer preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"ip" => ["is invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.PrimaryServer.create(
                   client(status, body),
                   1010,
                   name: "Primary",
                   ip: "192.0.2.1"
                 )

        assert_request(
          :post,
          "/v2/1010/secondary_dns/primaries",
          %{},
          %{"name" => "Primary", "ip" => "192.0.2.1"}
        )

        refute_received {:request, _request}
      end
    end

    test "createPrimaryServer returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@primary_server_data, "linked_secondary_zones")},
        %{"data" => Map.put(@primary_server_data, "linked_secondary_zones", nil)},
        %{"data" => Map.put(@primary_server_data, "updated_at", nil)}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 201, response: ^body}} =
                 ReqDnsimple.PrimaryServer.create(
                   client(201, body),
                   1010,
                   name: "Primary",
                   ip: "192.0.2.1"
                 )

        assert_request(
          :post,
          "/v2/1010/secondary_dns/primaries",
          %{},
          %{"name" => "Primary", "ip" => "192.0.2.1"}
        )

        refute_received {:request, _request}
      end
    end

    test "createPrimaryServer rejects an unexpected success status" do
      body = %{"data" => @primary_server_data}

      assert {:error, %{status: 200, response: ^body}} =
               ReqDnsimple.PrimaryServer.create(
                 client(200, body),
                 1010,
                 name: "Primary",
                 ip: "192.0.2.1"
               )

      assert_request(
        :post,
        "/v2/1010/secondary_dns/primaries",
        %{},
        %{"name" => "Primary", "ip" => "192.0.2.1"}
      )

      refute_received {:request, _request}
    end

    test "createPrimaryServer preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.PrimaryServer.create(
                 transport_error_client(:timeout),
                 1010,
                 name: "Primary",
                 ip: "192.0.2.1"
               )
    end
  end

  describe "link/4" do
    test "linkPrimaryServer sends the zone once and returns the updated typed server" do
      data =
        Map.put(
          @primary_server_data,
          "linked_secondary_zones",
          ["secondary.example.test"]
        )

      assert {:ok,
              %ReqDnsimple.PrimaryServer{
                id: 1,
                account_id: 1010,
                name: "Offline primary",
                ip: "192.0.2.1",
                port: 5353,
                linked_secondary_zones: ["secondary.example.test"],
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.PrimaryServer.link(
                 client(200, %{"data" => data}),
                 1010,
                 1,
                 zone: "secondary.example.test"
               )

      assert_request(
        :put,
        "/v2/1010/secondary_dns/primaries/1/link",
        %{},
        %{"zone" => "secondary.example.test"}
      )

      refute_received {:request, _request}
    end

    test "linkPrimaryServer preserves zero identifiers and an empty zone" do
      data =
        Map.merge(@primary_server_data, %{
          "id" => 0,
          "account_id" => 0,
          "linked_secondary_zones" => [""]
        })

      assert {:ok,
              %ReqDnsimple.PrimaryServer{
                id: 0,
                account_id: 0,
                linked_secondary_zones: [""]
              }} =
               ReqDnsimple.PrimaryServer.link(
                 client(200, %{"data" => data}),
                 0,
                 0,
                 zone: ""
               )

      assert_request(
        :put,
        "/v2/0/secondary_dns/primaries/0/link",
        %{},
        %{"zone" => ""}
      )
    end

    test "linkPrimaryServer rejects invalid paths and attributes before HTTP" do
      request = client(200, %{"data" => @primary_server_data})

      for {account_id, primary_server_id, attrs} <- [
            {"1010", 1, [zone: "secondary.example.test"]},
            {nil, 1, [zone: "secondary.example.test"]},
            {1010, "1", [zone: "secondary.example.test"]},
            {1010, nil, [zone: "secondary.example.test"]},
            {1010, 1, [:invalid]},
            {1010, 1, [{:zone}]},
            {1010, 1, []},
            {1010, 1, [zone: nil]},
            {1010, 1, [zone: false]},
            {1010, 1, [zone: 0]},
            {1010, 1, [zone: []]},
            {1010, 1, [zone: %{}]},
            {1010, 1, [zone: "secondary.example.test", unknown: true]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.PrimaryServer.link(
                   request,
                   account_id,
                   primary_server_id,
                   attrs
                 )
      end

      refute_received {:request, _request}
    end

    test "linkPrimaryServer preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"zone" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.PrimaryServer.link(
                   client(status, body),
                   1010,
                   1,
                   zone: "secondary.example.test"
                 )

        assert_request(
          :put,
          "/v2/1010/secondary_dns/primaries/1/link",
          %{},
          %{"zone" => "secondary.example.test"}
        )

        refute_received {:request, _request}
      end
    end

    test "linkPrimaryServer returns explicit errors for malformed successful responses" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@primary_server_data, "linked_secondary_zones")},
        %{"data" => Map.put(@primary_server_data, "linked_secondary_zones", nil)},
        %{"data" => Map.put(@primary_server_data, "linked_secondary_zones", [nil])},
        %{"data" => Map.put(@primary_server_data, "updated_at", nil)}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.PrimaryServer.link(
                   client(200, body),
                   1010,
                   1,
                   zone: "secondary.example.test"
                 )

        assert_request(
          :put,
          "/v2/1010/secondary_dns/primaries/1/link",
          %{},
          %{"zone" => "secondary.example.test"}
        )

        refute_received {:request, _request}
      end
    end

    test "linkPrimaryServer preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.PrimaryServer.link(
                 transport_error_client(:timeout),
                 1010,
                 1,
                 zone: "secondary.example.test"
               )
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
