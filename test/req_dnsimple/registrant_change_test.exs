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

  @pagination %{
    "current_page" => 1,
    "per_page" => 1,
    "total_entries" => 1,
    "total_pages" => 1
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

  describe "list_page/3 and list/3" do
    test "listRegistrantChanges sends every filter once and returns typed changes" do
      pagination = %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}

      assert {:ok,
              {[
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
                 }
               ], ^pagination}} =
               ReqDnsimple.RegistrantChange.list_page(
                 client(200, %{"data" => [@registrant_change_data], "pagination" => pagination}),
                 1010,
                 sort: [id: :asc, id: :desc],
                 state: "completed",
                 domain_id: "100",
                 contact_id: "11",
                 page: 2,
                 per_page: 1
               )

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        %{
          "sort" => "id:asc,id:desc",
          "state" => "completed",
          "domain_id" => "100",
          "contact_id" => "11",
          "page" => 2,
          "per_page" => 1
        },
        nil
      )

      refute_received {:request, _request}
    end

    test "listRegistrantChanges alias preserves omitted filters, empty pages and lock dates" do
      dated = Map.put(@registrant_change_data, "irt_lock_lifted_by", "2026-09-02")

      assert {:ok,
              {[%ReqDnsimple.RegistrantChange{irt_lock_lifted_by: ~D[2026-09-02]}], @pagination}} =
               ReqDnsimple.RegistrantChange.list(
                 client(200, %{"data" => [dated], "pagination" => @pagination}),
                 0
               )

      assert_request(:get, "/v2/0/registrar/registrant_changes", %{}, nil)
      refute_received {:request, _request}

      empty_pagination = %{@pagination | "total_entries" => 0, "total_pages" => 0}

      assert {:ok, {[], ^empty_pagination}} =
               ReqDnsimple.RegistrantChange.list_page(
                 client(200, %{"data" => [], "pagination" => empty_pagination}),
                 1010
               )
    end

    test "listRegistrantChanges rejects invalid paths and options before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      for {account_id, opts} <- [
            {"1010", []},
            {nil, []},
            {1010, [:invalid]},
            {1010, [{:name}]},
            {1010, [unknown: true]},
            {1010, [state: nil]},
            {1010, [state: "open"]},
            {1010, [domain_id: 100]},
            {1010, [contact_id: 11]},
            {1010, [sort: [name: :asc]]},
            {1010, [sort: [id: :sideways]]},
            {1010, [page: 0]},
            {1010, [per_page: 0]},
            {1010, [per_page: 101]}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.RegistrantChange.list_page(request, account_id, opts)
      end

      refute_received {:request, _request}
    end

    test "listRegistrantChanges preserves HTTP and transport failures" do
      for status <- [400, 401, 403, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"state" => ["is invalid"]}
        }

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.RegistrantChange.list_page(client(status, body), 1010)

        assert_request(:get, "/v2/1010/registrar/registrant_changes", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.RegistrantChange.list_page(transport_error_client(:timeout), 1010)
    end

    test "listRegistrantChanges rejects malformed successful responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil, "pagination" => @pagination},
        %{
          "data" => [Map.delete(@registrant_change_data, "irt_lock_lifted_by")],
          "pagination" => @pagination
        },
        %{
          "data" => [Map.put(@registrant_change_data, "irt_lock_lifted_by", "invalid")],
          "pagination" => @pagination
        },
        %{
          "data" => [Map.put(@registrant_change_data, "extended_attributes", %{"key" => 1})],
          "pagination" => @pagination
        },
        %{"data" => [@registrant_change_data]},
        %{"data" => [@registrant_change_data], "pagination" => nil},
        %{
          "data" => [@registrant_change_data],
          "pagination" => Map.delete(@pagination, "total_entries")
        },
        %{"data" => [@registrant_change_data], "pagination" => %{@pagination | "per_page" => 0}}
      ]

      for body <- malformed_bodies do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.RegistrantChange.list_page(client(200, body), 1010)

        assert_request(:get, "/v2/1010/registrar/registrant_changes", %{}, nil)
        refute_received {:request, _request}
      end
    end
  end

  describe "list_all/3" do
    test "returns empty and one-page collections without extra requests" do
      empty_pagination = %{@pagination | "total_entries" => 0, "total_pages" => 0}

      assert {:ok, []} =
               ReqDnsimple.RegistrantChange.list_all(
                 client(200, %{"data" => [], "pagination" => empty_pagination}),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      refute_received {:request, _request}

      assert {:ok, [%ReqDnsimple.RegistrantChange{id: 1}]} =
               ReqDnsimple.RegistrantChange.list_all(
                 client(200, %{"data" => [@registrant_change_data], "pagination" => @pagination}),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      refute_received {:request, _request}
    end

    test "enumerates from page one while preserving filters, sorting and order" do
      second = Map.merge(@registrant_change_data, %{"id" => 2, "domain_id" => 200})

      pages = %{
        1 =>
          {[@registrant_change_data],
           %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}},
        2 =>
          {[second],
           %{@pagination | "current_page" => 2, "total_entries" => 2, "total_pages" => 2}}
      }

      assert {:ok,
              [
                %ReqDnsimple.RegistrantChange{id: 1, domain_id: 100},
                %ReqDnsimple.RegistrantChange{id: 2, domain_id: 200}
              ]} =
               ReqDnsimple.RegistrantChange.list_all(
                 page_client(pages),
                 1010,
                 sort: [id: :desc],
                 state: "pending",
                 domain_id: "",
                 contact_id: "",
                 per_page: 1
               )

      expected_query = %{
        "sort" => "id:desc",
        "state" => "pending",
        "domain_id" => "",
        "contact_id" => "",
        "per_page" => 1
      }

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        Map.put(expected_query, "page", 1)
      )

      assert_request(
        :get,
        "/v2/1010/registrar/registrant_changes",
        Map.put(expected_query, "page", 2)
      )

      refute_received {:request, _request}
    end

    test "rejects explicit pages and malformed option containers before HTTP" do
      request = client(200, %{"data" => [], "pagination" => @pagination})

      assert {:error, {:invalid_option, :page}} =
               ReqDnsimple.RegistrantChange.list_all(request, 1010, page: 2)

      for opts <- [[:invalid], [{:name}]] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.RegistrantChange.list_all(request, 1010, opts)
      end

      refute_received {:request, _request}
    end

    test "aborts on later-page failures and rejects non-progressing pagination" do
      first_page =
        %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error, %{status: 503, response: %{"message" => "unavailable"}}} =
               ReqDnsimple.RegistrantChange.list_all(
                 response_client(fn
                   1 -> {200, %{"data" => [@registrant_change_data], "pagination" => first_page}}
                   2 -> {503, %{"message" => "unavailable"}}
                 end),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 2})

      repeated = %{@pagination | "current_page" => 1, "total_entries" => 2, "total_pages" => 2}

      assert {:error, {:invalid_pagination, ^repeated}} =
               ReqDnsimple.RegistrantChange.list_all(
                 response_client(fn _page ->
                   {200, %{"data" => [@registrant_change_data], "pagination" => repeated}}
                 end),
                 1010
               )

      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 1})
      assert_request(:get, "/v2/1010/registrar/registrant_changes", %{"page" => 2})
      refute_received {:request, _request}
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
