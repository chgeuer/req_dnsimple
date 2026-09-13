defmodule ReqDnsimple.ZoneTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @zone_data %{
    "id" => 1,
    "account_id" => 1010,
    "name" => "example.test",
    "reverse" => false,
    "secondary" => false,
    "last_transferred_at" => nil,
    "active" => true,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  @record_data %{
    "id" => 401,
    "zone_id" => "example.test",
    "parent_id" => nil,
    "name" => "",
    "content" => "ns1.example.test",
    "ttl" => 3600,
    "priority" => nil,
    "type" => "NS",
    "regions" => ["global"],
    "system_record" => true,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  describe "activate/3" do
    test "activateZoneService sends one bodyless request and returns the active zone" do
      assert {:ok,
              %ReqDnsimple.Zone{
                id: 1,
                account_id: 1010,
                name: "example.test",
                reverse: false,
                secondary: false,
                last_transferred_at: nil,
                active: true,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.Zone.activate(
                 client(200, %{"data" => @zone_data}),
                 1010,
                 "example.test"
               )

      assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "activateZoneService accepts zero and empty path identifiers" do
      assert {:ok, %ReqDnsimple.Zone{}} =
               ReqDnsimple.Zone.activate(
                 client(200, %{"data" => @zone_data}),
                 0,
                 ""
               )

      assert_request(:put, "/v2/0/zones//activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "activateZoneService rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @zone_data})

      for {account_id, zone} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 42},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Zone.activate(request, account_id, zone)
      end

      refute_received {:request, _request}
    end

    test "activateZoneService preserves documented and shared HTTP failures" do
      for status <- [400, 401, 402, 403, 404, 412, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"zone" => ["cannot activate DNS service"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Zone.activate(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "activateZoneService returns explicit errors for malformed success" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => []},
        %{"data" => Map.delete(@zone_data, "last_transferred_at")},
        %{"data" => Map.put(@zone_data, "id", "1")},
        %{"data" => Map.put(@zone_data, "reverse", nil)},
        %{"data" => Map.put(@zone_data, "last_transferred_at", "not-a-timestamp")},
        %{"data" => Map.put(@zone_data, "created_at", nil)}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Zone.activate(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error, %{status: 201, response: %{"data" => @zone_data}}} =
               ReqDnsimple.Zone.activate(
                 client(201, %{"data" => @zone_data}),
                 1010,
                 "example.test"
               )

      assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "activateZoneService decodes a non-null transfer timestamp" do
      transferred_zone =
        Map.put(@zone_data, "last_transferred_at", "2026-08-31T09:15:00+02:00")

      assert {:ok, %ReqDnsimple.Zone{last_transferred_at: ~U[2026-08-31 07:15:00Z]}} =
               ReqDnsimple.Zone.activate(
                 client(200, %{"data" => transferred_zone}),
                 1010,
                 "example.test"
               )

      assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "activateZoneService preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Zone.activate(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "deactivate/3" do
    test "deactivateZoneService sends one bodyless request and returns the inactive zone" do
      inactive_zone = Map.put(@zone_data, "active", false)

      assert {:ok,
              %ReqDnsimple.Zone{
                id: 1,
                account_id: 1010,
                name: "example.test",
                reverse: false,
                secondary: false,
                last_transferred_at: nil,
                active: false,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.Zone.deactivate(
                 client(200, %{"data" => inactive_zone}),
                 1010,
                 "example.test"
               )

      assert_request(:delete, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "deactivateZoneService accepts zero and empty path identifiers" do
      inactive_zone = Map.put(@zone_data, "active", false)

      assert {:ok, %ReqDnsimple.Zone{active: false}} =
               ReqDnsimple.Zone.deactivate(
                 client(200, %{"data" => inactive_zone}),
                 0,
                 ""
               )

      assert_request(:delete, "/v2/0/zones//activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "deactivateZoneService rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => Map.put(@zone_data, "active", false)})

      for {account_id, zone} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 42},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Zone.deactivate(request, account_id, zone)
      end

      refute_received {:request, _request}
    end

    test "deactivateZoneService preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"zone" => ["cannot deactivate DNS service"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Zone.deactivate(
                   client(status, body),
                   1010,
                   "example.test"
                 )

        assert_request(:delete, "/v2/1010/zones/example.test/activation", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deactivateZoneService returns explicit errors for malformed success" do
      inactive_zone = Map.put(@zone_data, "active", false)

      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => []},
        %{"data" => Map.delete(inactive_zone, "last_transferred_at")},
        %{"data" => Map.put(inactive_zone, "id", "1")},
        %{"data" => Map.put(inactive_zone, "active", nil)},
        %{"data" => Map.put(inactive_zone, "last_transferred_at", "not-a-timestamp")},
        %{"data" => Map.put(inactive_zone, "created_at", nil)}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Zone.deactivate(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:delete, "/v2/1010/zones/example.test/activation", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error, %{status: 204, response: nil}} =
               ReqDnsimple.Zone.deactivate(
                 client(204, nil),
                 1010,
                 "example.test"
               )

      assert_request(:delete, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "deactivateZoneService decodes a non-null transfer timestamp" do
      inactive_zone =
        @zone_data
        |> Map.put("active", false)
        |> Map.put("last_transferred_at", "2026-08-31T09:15:00+02:00")

      assert {:ok,
              %ReqDnsimple.Zone{
                active: false,
                last_transferred_at: ~U[2026-08-31 07:15:00Z]
              }} =
               ReqDnsimple.Zone.deactivate(
                 client(200, %{"data" => inactive_zone}),
                 1010,
                 "example.test"
               )

      assert_request(:delete, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "deactivateZoneService preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Zone.deactivate(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end
  end

  describe "update_ns_records/4" do
    test "updateZoneNsRecords sends both selections once and returns typed records" do
      attrs = [
        ns_names: ["ns1.example.test", "ns2.example.test"],
        ns_set_ids: [7]
      ]

      assert {:ok,
              [
                %ReqDnsimple.ZoneRecord{
                  id: 401,
                  zone_id: "example.test",
                  parent_id: nil,
                  name: "",
                  content: "ns1.example.test",
                  ttl: 3600,
                  priority: nil,
                  type: "NS",
                  regions: ["global"],
                  system_record: true,
                  created_at: ~U[2026-09-01 08:00:00Z],
                  updated_at: ~U[2026-09-01 08:30:00Z]
                }
              ]} =
               ReqDnsimple.Zone.update_ns_records(
                 client(200, %{"data" => [@record_data]}),
                 1010,
                 "example.test",
                 attrs
               )

      assert_request(
        :put,
        "/v2/1010/zones/example.test/ns_records",
        %{},
        Map.new(attrs)
      )

      refute_received {:request, _request}
    end

    test "accepts either selector, numeric zone IDs, and explicit empty arrays" do
      cases = [
        {"example.test", [ns_names: ["ns1.example.test"]]},
        {42, [ns_set_ids: [7]]},
        {"example.test", [ns_names: []]},
        {0, [ns_set_ids: []]}
      ]

      for {zone, attrs} <- cases do
        assert {:ok, []} =
                 ReqDnsimple.Zone.update_ns_records(
                   client(200, %{"data" => []}),
                   1010,
                   zone,
                   attrs
                 )

        assert_request(
          :put,
          "/v2/1010/zones/#{zone}/ns_records",
          %{},
          Map.new(attrs)
        )

        refute_received {:request, _request}
      end
    end

    test "rejects missing, unknown, null, and incorrectly typed inputs before HTTP" do
      request = client(200, %{"data" => []})

      invalid_calls = [
        {1010, "example.test", []},
        {1010, "example.test", [:invalid]},
        {1010, "example.test", [{:name}]},
        {1010, "example.test", [unknown: []]},
        {1010, "example.test", [ns_names: nil]},
        {1010, "example.test", [ns_names: ["ns1.example.test", nil]]},
        {1010, "example.test", [ns_set_ids: ["7"]]},
        {1010, "example.test", %{"ns_names" => []}},
        {"1010", "example.test", [ns_names: []]},
        {1010, nil, [ns_names: []]},
        {1010, 1.0, [ns_names: []]}
      ]

      for {account_id, zone, attrs} <- invalid_calls do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.Zone.update_ns_records(request, account_id, zone, attrs)
      end

      refute_received {:request, _request}
    end

    test "preserves documented and shared HTTP failures" do
      for status <- [400, 401, 402, 403, 404, 412, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"ns_names" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.Zone.update_ns_records(
                   client(status, body),
                   1010,
                   "example.test",
                   ns_names: []
                 )

        assert_request(:put, "/v2/1010/zones/example.test/ns_records", %{}, %{
          ns_names: []
        })

        refute_received {:request, _request}
      end
    end

    test "returns explicit errors for malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => %{}},
        %{"data" => [Map.delete(@record_data, "ttl")]},
        %{"data" => [Map.put(@record_data, "ttl", "3600")]},
        %{"data" => [Map.put(@record_data, "type", "INVALID")]},
        %{"data" => [Map.put(@record_data, "regions", [nil])]},
        %{"data" => [Map.put(@record_data, "created_at", "not-a-timestamp")]}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.Zone.update_ns_records(
                   client(200, body),
                   1010,
                   "example.test",
                   ns_set_ids: [7]
                 )

        assert_request(
          :put,
          "/v2/1010/zones/example.test/ns_records",
          %{},
          %{ns_set_ids: [7]}
        )

        refute_received {:request, _request}
      end
    end

    test "preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.Zone.update_ns_records(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 ns_names: ["ns1.example.test"]
               )
    end
  end
end
