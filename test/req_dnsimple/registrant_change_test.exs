defmodule ReqDnsimple.RegistrantChangeTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @registrant_change_data %{
    "id" => 1,
    "account_id" => 1010,
    "contact_id" => 11,
    "domain_id" => 100,
    "state" => "pending",
    "extended_attributes" => %{"x-fi-registrant-idnumber" => "fake-offline-id"},
    "registry_owner_change" => true,
    "irt_lock_lifted_by" => nil,
    "created_at" => "2026-09-01T10:00:00+02:00",
    "updated_at" => "2026-09-01T10:30:00+02:00"
  }

  describe "create/3" do
    test "createRegistrantChange sends every supplied field once and returns a typed change" do
      completed_data = Map.put(@registrant_change_data, "state", "completed")

      assert {:ok,
              %ReqDnsimple.RegistrantChange{
                id: 1,
                account_id: 1010,
                contact_id: 11,
                domain_id: 100,
                state: "completed",
                extended_attributes: %{
                  "x-fi-registrant-idnumber" => "fake-offline-id"
                },
                registry_owner_change: true,
                irt_lock_lifted_by: nil,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.RegistrantChange.create(
                 client(201, %{"data" => completed_data}),
                 1010,
                 domain_id: "example.test",
                 contact_id: "11",
                 extended_attributes: %{
                   "x-fi-registrant-idnumber" => "fake-offline-id"
                 }
               )

      assert_request(
        :post,
        "/v2/1010/registrar/registrant_changes",
        %{},
        %{
          "domain_id" => "example.test",
          "contact_id" => "11",
          "extended_attributes" => %{
            "x-fi-registrant-idnumber" => "fake-offline-id"
          }
        }
      )

      refute_received {:request, _request}
    end

    test "createRegistrantChange accepts 202 and preserves omission, zero, empty strings and maps" do
      assert {:ok, %ReqDnsimple.RegistrantChange{state: "pending"}} =
               ReqDnsimple.RegistrantChange.create(
                 client(202, %{"data" => @registrant_change_data}),
                 0,
                 domain_id: "",
                 contact_id: 0
               )

      assert_request(
        :post,
        "/v2/0/registrar/registrant_changes",
        %{},
        %{"domain_id" => "", "contact_id" => 0}
      )

      assert {:ok, %ReqDnsimple.RegistrantChange{extended_attributes: %{}}} =
               ReqDnsimple.RegistrantChange.create(
                 client(201, %{
                   "data" => Map.put(@registrant_change_data, "extended_attributes", %{})
                 }),
                 1010,
                 domain_id: 100,
                 contact_id: "11",
                 extended_attributes: %{}
               )

      assert_request(
        :post,
        "/v2/1010/registrar/registrant_changes",
        %{},
        %{"domain_id" => 100, "contact_id" => "11", "extended_attributes" => %{}}
      )

      refute_received {:request, _request}
    end

    test "createRegistrantChange rejects invalid attributes before HTTP" do
      request = client(201, %{"data" => @registrant_change_data})

      for {account_id, attrs} <- [
            {"1010", [domain_id: "example.test", contact_id: 11]},
            {nil, [domain_id: "example.test", contact_id: 11]},
            {1010, [:invalid]},
            {1010, [{:domain_id}]},
            {1010, []},
            {1010, [domain_id: "example.test"]},
            {1010, [contact_id: 11]},
            {1010, [domain_id: nil, contact_id: 11]},
            {1010, [domain_id: false, contact_id: 11]},
            {1010, [domain_id: [], contact_id: 11]},
            {1010, [domain_id: "example.test", contact_id: nil]},
            {1010, [domain_id: "example.test", contact_id: false]},
            {1010, [domain_id: "example.test", contact_id: []]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: nil
             ]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: %{"key" => 1}
             ]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: %{key: "value"}
             ]},
            {1010,
             [
               domain_id: "example.test",
               contact_id: 11,
               extended_attributes: MapSet.new()
             ]},
            {1010, [domain_id: "example.test", contact_id: 11, unknown: true]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.RegistrantChange.create(request, account_id, attrs)
      end

      refute_received {:request, _request}
    end

    test "createRegistrantChange preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"contact_id" => ["is invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.RegistrantChange.create(
                   client(status, body),
                   1010,
                   domain_id: "example.test",
                   contact_id: 11
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/registrant_changes",
          %{},
          %{"domain_id" => "example.test", "contact_id" => 11}
        )

        refute_received {:request, _request}
      end
    end

    test "createRegistrantChange returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@registrant_change_data, "id")},
        %{"data" => Map.put(@registrant_change_data, "state", "unknown")},
        %{"data" => Map.put(@registrant_change_data, "extended_attributes", %{"key" => 1})},
        %{"data" => Map.put(@registrant_change_data, "irt_lock_lifted_by", "not-a-date")},
        %{"data" => Map.put(@registrant_change_data, "updated_at", nil)}
      ]

      for {status, body} <-
            Enum.map(malformed_payloads, &{201, &1}) ++
              [{202, %{"data" => nil}}, {200, %{"data" => @registrant_change_data}}] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.RegistrantChange.create(
                   client(status, body),
                   1010,
                   domain_id: "example.test",
                   contact_id: 11
                 )

        assert_request(
          :post,
          "/v2/1010/registrar/registrant_changes",
          %{},
          %{"domain_id" => "example.test", "contact_id" => 11}
        )

        refute_received {:request, _request}
      end
    end

    test "createRegistrantChange preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.RegistrantChange.create(
                 transport_error_client(:timeout),
                 1010,
                 domain_id: "example.test",
                 contact_id: 11
               )
    end
  end

  describe "get/3" do
    test "getRegistrantChange sends one bodyless request and returns a typed change" do
      assert {:ok,
              %ReqDnsimple.RegistrantChange{
                id: 1,
                account_id: 1010,
                contact_id: 11,
                domain_id: 100,
                state: "pending",
                extended_attributes: %{
                  "x-fi-registrant-idnumber" => "fake-offline-id"
                },
                registry_owner_change: true,
                irt_lock_lifted_by: nil,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.RegistrantChange.get(
                 client(200, %{"data" => @registrant_change_data}),
                 1010,
                 1
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "getRegistrantChange preserves every state and valid false, zero, empty, and date values" do
      for state <- ["new", "pending", "cancelling", "cancelled", "completed"] do
        data =
          Map.merge(@registrant_change_data, %{
            "id" => 0,
            "account_id" => 0,
            "contact_id" => 0,
            "domain_id" => 0,
            "state" => state,
            "extended_attributes" => %{},
            "registry_owner_change" => false,
            "irt_lock_lifted_by" => "2026-09-02"
          })

        assert {:ok,
                %ReqDnsimple.RegistrantChange{
                  id: 0,
                  account_id: 0,
                  contact_id: 0,
                  domain_id: 0,
                  state: ^state,
                  extended_attributes: %{},
                  registry_owner_change: false,
                  irt_lock_lifted_by: ~D[2026-09-02]
                }} =
                 ReqDnsimple.RegistrantChange.get(
                   client(200, %{"data" => data}),
                   0,
                   0
                 )

        assert_request(:get, "/v2/0/registrar/registrant_changes/0", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getRegistrantChange rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @registrant_change_data})

      for {account_id, registrant_change_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, "1"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.RegistrantChange.get(
                   request,
                   account_id,
                   registrant_change_id
                 )
      end

      refute_received {:request, _request}
    end

    test "getRegistrantChange preserves documented and shared HTTP failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"registrant_change" => ["is unavailable"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.RegistrantChange.get(client(status, body), 1010, 1)

        assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getRegistrantChange returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@registrant_change_data, "id")},
        %{"data" => Map.put(@registrant_change_data, "account_id", "1010")},
        %{"data" => Map.put(@registrant_change_data, "state", "unknown")},
        %{"data" => Map.put(@registrant_change_data, "extended_attributes", %{key: "value"})},
        %{
          "data" =>
            Map.put(
              @registrant_change_data,
              "extended_attributes",
              %{"key" => 1}
            )
        },
        %{"data" => Map.put(@registrant_change_data, "registry_owner_change", 1)},
        %{"data" => Map.put(@registrant_change_data, "irt_lock_lifted_by", "not-a-date")},
        %{"data" => Map.put(@registrant_change_data, "created_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.RegistrantChange.get(client(200, body), 1010, 1)

        assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [
            {201, %{"data" => @registrant_change_data}},
            {204, nil}
          ] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.RegistrantChange.get(client(status, body), 1010, 1)

        assert_request(:get, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "getRegistrantChange preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.RegistrantChange.get(
                 transport_error_client(:timeout),
                 1010,
                 1
               )
    end
  end

  describe "cancel/3" do
    test "deleteRegistrantChange sends one bodyless request and returns a cancelling change" do
      data = Map.put(@registrant_change_data, "state", "cancelling")

      assert {:ok,
              %ReqDnsimple.RegistrantChange{
                id: 1,
                account_id: 1010,
                contact_id: 11,
                domain_id: 100,
                state: "cancelling",
                extended_attributes: %{
                  "x-fi-registrant-idnumber" => "fake-offline-id"
                },
                registry_owner_change: true,
                irt_lock_lifted_by: nil,
                created_at: ~U[2026-09-01 08:00:00Z],
                updated_at: ~U[2026-09-01 08:30:00Z]
              }} =
               ReqDnsimple.RegistrantChange.cancel(
                 client(202, %{"data" => data}),
                 1010,
                 1
               )

      assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteRegistrantChange returns :ok for immediate cancellation" do
      assert :ok = ReqDnsimple.RegistrantChange.cancel(client(204, nil), 1010, 1)

      assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteRegistrantChange preserves zero values, empty attributes, false and a lock date" do
      data =
        Map.merge(@registrant_change_data, %{
          "id" => 0,
          "account_id" => 0,
          "contact_id" => 0,
          "domain_id" => 0,
          "state" => "cancelled",
          "extended_attributes" => %{},
          "registry_owner_change" => false,
          "irt_lock_lifted_by" => "2026-09-02"
        })

      assert {:ok,
              %ReqDnsimple.RegistrantChange{
                id: 0,
                account_id: 0,
                contact_id: 0,
                domain_id: 0,
                state: "cancelled",
                extended_attributes: %{},
                registry_owner_change: false,
                irt_lock_lifted_by: ~D[2026-09-02]
              }} =
               ReqDnsimple.RegistrantChange.cancel(client(202, %{"data" => data}), 0, 0)

      assert_request(:delete, "/v2/0/registrar/registrant_changes/0", %{}, nil)
      refute_received {:request, _request}
    end

    test "deleteRegistrantChange rejects invalid path parameters before HTTP" do
      request = client(204, nil)

      for {account_id, registrant_change_id} <- [
            {"1010", 1},
            {nil, 1},
            {1010, "1"},
            {1010, nil},
            {1010, 1.5},
            {1010, []}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.RegistrantChange.cancel(
                   request,
                   account_id,
                   registrant_change_id
                 )
      end

      refute_received {:request, _request}
    end

    test "deleteRegistrantChange preserves documented and shared HTTP failures" do
      for status <- [400, 401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"registrant_change" => ["cannot be cancelled"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.RegistrantChange.cancel(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteRegistrantChange returns explicit errors for malformed success" do
      malformed_payloads = [
        %{},
        %{"data" => nil},
        %{"data" => Map.delete(@registrant_change_data, "id")},
        %{"data" => Map.put(@registrant_change_data, "account_id", "1010")},
        %{"data" => Map.put(@registrant_change_data, "state", "unknown")},
        %{"data" => Map.put(@registrant_change_data, "extended_attributes", %{key: "value"})},
        %{"data" => Map.put(@registrant_change_data, "registry_owner_change", 1)},
        %{"data" => Map.put(@registrant_change_data, "irt_lock_lifted_by", "not-a-date")},
        %{"data" => Map.put(@registrant_change_data, "updated_at", "not-a-timestamp")}
      ]

      for body <- malformed_payloads do
        assert {:error, %{status: 202, response: ^body}} =
                 ReqDnsimple.RegistrantChange.cancel(client(202, body), 1010, 1)

        assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end

      for {status, body} <- [
            {200, %{"data" => @registrant_change_data}},
            {201, %{"data" => @registrant_change_data}},
            {205, nil}
          ] do
        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.RegistrantChange.cancel(client(status, body), 1010, 1)

        assert_request(:delete, "/v2/1010/registrar/registrant_changes/1", %{}, nil)
        refute_received {:request, _request}
      end
    end

    test "deleteRegistrantChange preserves transport failures" do
      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.RegistrantChange.cancel(
                 transport_error_client(:timeout),
                 1010,
                 1
               )
    end
  end
end
