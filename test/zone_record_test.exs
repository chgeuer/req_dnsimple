defmodule ReqDnsimple.ZoneRecordTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @record_data %{
    "id" => 1,
    "zone_id" => "example.com",
    "name" => "",
    "content" => "mail.example.com",
    "ttl" => 0,
    "priority" => 0,
    "type" => "MX",
    "regions" => ["global"],
    "parent_id" => nil,
    "system_record" => false,
    "created_at" => "2024-01-01T00:00:00Z",
    "updated_at" => "2024-01-02T00:00:00Z"
  }

  test "create accepts and transmits explicit zero TTL and priority for apex records" do
    attrs = [name: "", type: "MX", content: "mail.example.com", ttl: 0, priority: 0]

    assert {:ok, %ReqDnsimple.ZoneRecord{ttl: 0, priority: 0}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => @record_data}),
               1010,
               "example.com",
               attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(attrs))
  end

  test "update transmits explicit zero without adding omitted fields" do
    assert {:ok, %ReqDnsimple.ZoneRecord{ttl: 0, priority: 0}} =
             ReqDnsimple.ZoneRecord.update(
               client(200, %{"data" => @record_data}),
               1010,
               "example.com",
               1,
               ttl: 0,
               priority: 0
             )

    assert_request(
      :patch,
      "/v2/1010/zones/example.com/records/1",
      %{},
      %{ttl: 0, priority: 0}
    )
  end

  test "create and update transmit explicit integrated zone selections" do
    create_attrs = [
      name: "",
      type: "MX",
      content: "mail.example.com",
      integrated_zones: [1, 2, "dnsimple"]
    ]

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 1}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => @record_data}),
               1010,
               "example.com",
               create_attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(create_attrs))

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 1}} =
             ReqDnsimple.ZoneRecord.update(
               client(200, %{"data" => @record_data}),
               1010,
               "example.com",
               1,
               integrated_zones: ["dnsimple"]
             )

    assert_request(
      :patch,
      "/v2/1010/zones/example.com/records/1",
      %{},
      %{integrated_zones: ["dnsimple"]}
    )
  end

  test "create and update transmit explicit empty integrated zone selections" do
    create_attrs = [
      name: "",
      type: "MX",
      content: "mail.example.com",
      integrated_zones: []
    ]

    assert {:ok, %ReqDnsimple.ZoneRecord{}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => @record_data}),
               1010,
               "example.com",
               create_attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(create_attrs))

    assert {:ok, %ReqDnsimple.ZoneRecord{}} =
             ReqDnsimple.ZoneRecord.update(
               client(200, %{"data" => @record_data}),
               1010,
               "example.com",
               1,
               integrated_zones: []
             )

    assert_request(
      :patch,
      "/v2/1010/zones/example.com/records/1",
      %{},
      %{integrated_zones: []}
    )
  end

  test "create and update reject invalid integrated zone items before HTTP" do
    create_client = client(201, %{"data" => @record_data})
    update_client = client(200, %{"data" => @record_data})
    required = [name: "", type: "MX", content: "mail.example.com"]

    for integrated_zones <- [[1.0], ["1"], ["other"], [:dnsimple], [nil]] do
      assert {:error, %NimbleOptions.ValidationError{key: :integrated_zones}} =
               ReqDnsimple.ZoneRecord.create(
                 create_client,
                 1010,
                 "example.com",
                 required ++ [integrated_zones: integrated_zones]
               )

      assert {:error, %NimbleOptions.ValidationError{key: :integrated_zones}} =
               ReqDnsimple.ZoneRecord.update(
                 update_client,
                 1010,
                 "example.com",
                 1,
                 integrated_zones: integrated_zones
               )
    end

    refute_received {:request, _request}
  end

  test "integrated zone mutations preserve API and transport errors" do
    assert {:error, %{status: 503, response: %{"message" => "unavailable"}}} =
             ReqDnsimple.ZoneRecord.create(
               client(503, %{"message" => "unavailable"}),
               1010,
               "example.com",
               name: "",
               type: "MX",
               content: "mail.example.com",
               integrated_zones: ["dnsimple"]
             )

    assert_request(
      :post,
      "/v2/1010/zones/example.com/records",
      %{},
      %{
        name: "",
        type: "MX",
        content: "mail.example.com",
        integrated_zones: ["dnsimple"]
      }
    )

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             ReqDnsimple.ZoneRecord.update(
               transport_error_client(:econnrefused),
               1010,
               "example.com",
               1,
               integrated_zones: [1, "dnsimple"]
             )
  end

  test "create and update reject negative and incorrectly typed values before HTTP" do
    create_client = client(201, %{"data" => @record_data})
    required = [name: "", type: "MX", content: "mail.example.com"]

    for invalid_attrs <- [
          required ++ [ttl: -1],
          required ++ [ttl: "0"],
          required ++ [priority: -1],
          required ++ [priority: "0"]
        ] do
      assert {:error, %NimbleOptions.ValidationError{}} =
               ReqDnsimple.ZoneRecord.create(
                 create_client,
                 1010,
                 "example.com",
                 invalid_attrs
               )
    end

    update_client = client(200, %{"data" => @record_data})

    for invalid_attrs <- [[ttl: -1], [ttl: "0"], [priority: -1], [priority: "0"]] do
      assert {:error, %NimbleOptions.ValidationError{}} =
               ReqDnsimple.ZoneRecord.update(
                 update_client,
                 1010,
                 "example.com",
                 1,
                 invalid_attrs
               )
    end

    refute_received {:request, _request}
  end

  test "create still requires name, type, and content" do
    assert {:error, %NimbleOptions.ValidationError{}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => @record_data}),
               1010,
               "example.com",
               type: "MX",
               content: "mail.example.com"
             )

    refute_received {:request, _request}
  end

  describe "check_distribution/4" do
    test "checks one record once and preserves both boolean results" do
      for distributed <- [true, false] do
        assert {:ok, ^distributed} =
                 ReqDnsimple.ZoneRecord.check_distribution(
                   client(200, %{"data" => %{"distributed" => distributed}}),
                   1010,
                   "example.test",
                   1
                 )

        assert_request(
          :get,
          "/v2/1010/zones/example.test/records/1/distribution",
          %{},
          nil
        )

        refute_received {:request, _request}
      end
    end

    test "preserves endpoint-specific and generic HTTP failures" do
      body = %{"message" => "Fake offline request failure"}

      for {status, expected} <- [
            {401, {:error, :unauthorized}},
            {404, {:error, :not_found}},
            {504, {:error, :timeout}},
            {403, {:error, %{status: 403, response: body}}},
            {429, {:error, %{status: 429, response: body}}},
            {500, {:error, %{status: 500, response: body}}}
          ] do
        assert ReqDnsimple.ZoneRecord.check_distribution(
                 client(status, body),
                 1010,
                 "example.test",
                 1
               ) == expected

        assert_request(:get, "/v2/1010/zones/example.test/records/1/distribution")
        refute_received {:request, _request}
      end
    end

    test "returns explicit errors for malformed success and transport timeout" do
      for body <- [
            %{},
            %{"data" => %{}},
            %{"data" => %{"distributed" => nil}},
            %{"data" => %{"distributed" => "true"}}
          ] do
        assert {:error, %{status: 200, response: ^body}} =
                 ReqDnsimple.ZoneRecord.check_distribution(
                   client(200, body),
                   1010,
                   "example.test",
                   1
                 )
      end

      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.ZoneRecord.check_distribution(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 1
               )
    end

    test "rejects invalid path parameter types before HTTP" do
      request = client(200, %{"data" => %{"distributed" => true}})

      for {account_id, zone_name, record_id} <- [
            {"1010", "example.test", 1},
            {1010, nil, 1},
            {1010, "example.test", "1"}
          ] do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.ZoneRecord.check_distribution(
                   request,
                   account_id,
                   zone_name,
                   record_id
                 )
      end

      refute_received {:request, _request}
    end
  end

  describe "batch_change/4" do
    test "sends all operations once and returns typed results" do
      attrs = [
        creates: [
          [
            name: "",
            type: "MX",
            content: "mail.example.test",
            ttl: 0,
            priority: 0,
            regions: ["global"]
          ]
        ],
        updates: [
          [
            id: 302,
            name: "www",
            content: "192.0.2.2",
            ttl: 0,
            priority: 0,
            regions: []
          ]
        ],
        deletes: [[id: 303]]
      ]

      created = Map.put(@record_data, "id", 301)

      updated =
        Map.merge(@record_data, %{
          "id" => 302,
          "name" => "www",
          "content" => "192.0.2.2",
          "type" => "A",
          "regions" => []
        })

      assert {:ok,
              %ReqDnsimple.ZoneRecord.BatchResult{
                creates: [%ReqDnsimple.ZoneRecord{id: 301, parent_id: nil, ttl: 0}],
                updates: [%ReqDnsimple.ZoneRecord{id: 302, regions: []}],
                deletes: [%ReqDnsimple.ZoneRecord.DeletedRecord{id: 303}]
              }} =
               ReqDnsimple.ZoneRecord.batch_change(
                 client(200, %{
                   "data" => %{
                     "creates" => [created],
                     "updates" => [updated],
                     "deletes" => [%{"id" => 303}]
                   }
                 }),
                 1010,
                 "example.test",
                 attrs
               )

      assert_request(:post, "/v2/1010/zones/example.test/batch", %{}, %{
        creates: [
          %{
            name: "",
            type: "MX",
            content: "mail.example.test",
            ttl: 0,
            priority: 0,
            regions: ["global"]
          }
        ],
        updates: [
          %{
            id: 302,
            name: "www",
            content: "192.0.2.2",
            ttl: 0,
            priority: 0,
            regions: []
          }
        ],
        deletes: [%{id: 303}]
      })

      refute_received {:request, _request}
    end

    test "preserves omitted and explicit empty operation arrays" do
      empty_result = %{
        "data" => %{"creates" => [], "updates" => [], "deletes" => []}
      }

      for attrs <- [
            [],
            [creates: [[name: "", type: "A", content: "192.0.2.1"]]],
            [creates: [%{name: "", type: "A", content: "192.0.2.1"}]],
            [updates: [[id: 0]], deletes: [[id: 0]]],
            [creates: [], updates: [], deletes: []]
          ] do
        assert {:ok, %ReqDnsimple.ZoneRecord.BatchResult{}} =
                 ReqDnsimple.ZoneRecord.batch_change(
                   client(200, empty_result),
                   1010,
                   "example.test",
                   attrs
                 )

        expected =
          attrs
          |> Map.new(fn {operation, items} ->
            {operation, Enum.map(items, &Map.new/1)}
          end)
          |> Jason.encode!()
          |> Jason.decode!()

        assert_request(:post, "/v2/1010/zones/example.test/batch", %{}, expected)
      end
    end

    test "rejects invalid and unknown operation attributes before HTTP" do
      request = client(200, %{})

      invalid_attrs = [
        [creates: [[type: "A", content: "192.0.2.1"]]],
        [creates: [[name: "", type: "INVALID", content: "192.0.2.1"]]],
        [creates: [[name: "", type: "A", content: nil]]],
        [creates: [[name: "", type: "A", content: "192.0.2.1", ttl: -1]]],
        [creates: [[name: "", type: "A", content: "192.0.2.1", regions: ["moon"]]]],
        [updates: [[content: "192.0.2.2"]]],
        [updates: [[id: 302, type: "AAAA"]]],
        [deletes: [303]],
        [deletes: [[id: "303"]]],
        [unknown: []]
      ]

      for attrs <- invalid_attrs do
        assert {:error, %NimbleOptions.ValidationError{}} =
                 ReqDnsimple.ZoneRecord.batch_change(request, 1010, "example.test", attrs)
      end

      refute_received {:request, _request}
    end

    test "preserves indexed validation errors and generic HTTP failures" do
      validation_body = %{
        "message" => "Fake offline validation failure",
        "errors" => %{
          "creates" => [
            %{
              "index" => 0,
              "message" => "Fake duplicate record",
              "errors" => %{"base" => ["Fake duplicate record"]}
            }
          ],
          "updates" => nil,
          "deletes" => []
        }
      }

      assert {:error,
              %{
                status: 400,
                message: "Fake offline validation failure",
                errors: errors
              }} =
               ReqDnsimple.ZoneRecord.batch_change(
                 client(400, validation_body),
                 1010,
                 "example.test",
                 []
               )

      assert errors == validation_body["errors"]

      for status <- [401, 403, 404, 412, 429, 500] do
        body = %{"message" => "failure #{status}"}

        assert {:error, %{status: ^status, response: ^body}} =
                 ReqDnsimple.ZoneRecord.batch_change(
                   client(status, body),
                   1010,
                   "example.test",
                   []
                 )
      end
    end

    test "returns explicit errors for malformed success and transport failures" do
      malformed = %{"data" => %{"creates" => [], "updates" => []}}

      assert {:error, %{status: 200, response: ^malformed}} =
               ReqDnsimple.ZoneRecord.batch_change(
                 client(200, malformed),
                 1010,
                 "example.test",
                 []
               )

      malformed_timestamp =
        put_in(
          %{
            "data" => %{
              "creates" => [@record_data],
              "updates" => [],
              "deletes" => []
            }
          },
          ["data", "creates", Access.at(0), "created_at"],
          "not-a-timestamp"
        )

      assert {:error, %{status: 200, response: ^malformed_timestamp}} =
               ReqDnsimple.ZoneRecord.batch_change(
                 client(200, malformed_timestamp),
                 1010,
                 "example.test",
                 []
               )

      assert {:error, %Req.TransportError{reason: :timeout}} =
               ReqDnsimple.ZoneRecord.batch_change(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 []
               )
    end
  end
end
