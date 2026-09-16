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

  test "preserves HTTP headers on every zone-record operation and generic HTTP errors" do
    headers = [
      {"x-request-id", "record-response"},
      {"x-ratelimit-remaining", "0"},
      {"retry-after", "5"}
    ]

    pagination = %{
      "current_page" => 1,
      "per_page" => 1,
      "total_entries" => 1,
      "total_pages" => 1
    }

    create =
      &ReqDnsimple.ZoneRecord.create(&1, 1010, "example.com",
        name: "",
        type: "MX",
        content: "mail.example.com",
        priority: nil
      )

    for {operation, status, body, page} <- [
          {create, 201, %{"data" => @record_data}, nil},
          {create, 200, %{"data" => @record_data}, nil},
          {&ReqDnsimple.ZoneRecord.get(&1, 1010, "example.com", 1), 200,
           %{"data" => @record_data}, nil},
          {&ReqDnsimple.ZoneRecord.update(&1, 1010, "example.com", 1, priority: nil), 200,
           %{"data" => @record_data}, nil},
          {&ReqDnsimple.ZoneRecord.list_page(&1, 1010, "example.com"), 200,
           %{"data" => [@record_data], "pagination" => pagination}, pagination},
          {&ReqDnsimple.ZoneRecord.check_distribution(&1, 1010, "example.com", 1), 200,
           %{"data" => %{"distributed" => false}}, nil},
          {&ReqDnsimple.ZoneRecord.batch_change(&1, 1010, "example.com", creates: []), 200,
           %{"data" => %{"creates" => [], "updates" => [], "deletes" => []}}, nil},
          {&ReqDnsimple.ZoneRecord.delete(&1, 1010, "example.com", 1), 204, nil, nil}
        ] do
      metadata = %ReqDnsimple.Metadata{
        status: status,
        pagination: page,
        request_id: "record-response",
        rate_limit_remaining: 0,
        retry_after: "5"
      }

      assert {:ok, {data, ^metadata}} = operation.(client(status, body, self(), headers))
      if status == 204, do: assert(is_nil(data))
      assert_received {:request, _request}

      error_body = %{"message" => "retry later"}
      error_reason = %{status: 429, response: error_body}
      error_metadata = %{metadata | status: 429, pagination: nil}

      assert {:error, %ReqDnsimple.Error{reason: ^error_reason, metadata: ^error_metadata}} =
               operation.(client(429, error_body, self(), headers))

      assert_received {:request, _request}
      refute_received {:request, _request}
    end
  end

  test "mapped zone-record mutation errors preserve reasons and response metadata" do
    create =
      &ReqDnsimple.ZoneRecord.create(&1, 1010, "example.com",
        name: "",
        type: "A",
        content: "192.0.2.1"
      )

    update = &ReqDnsimple.ZoneRecord.update(&1, 1010, "example.com", 1, content: "192.0.2.1")
    batch = &ReqDnsimple.ZoneRecord.batch_change(&1, 1010, "example.com", creates: [])
    errors = %{"content" => ["offline validation error"]}
    body = %{"message" => "invalid", "errors" => errors}
    reason = %{status: 400, message: "invalid", errors: errors}

    for operation <- [create, update, batch] do
      req = client(400, body, self(), [{"x-request-id", "record-validation"}])

      assert {:error,
              %ReqDnsimple.Error{
                reason: ^reason,
                metadata: %ReqDnsimple.Metadata{status: 400, request_id: "record-validation"}
              }} = operation.(req)

      assert_received {:request, _request}
      refute_received {:request, _request}
    end

    for operation <- [
          create,
          update,
          &ReqDnsimple.ZoneRecord.get(&1, 1010, "example.com", 1),
          &ReqDnsimple.ZoneRecord.list_page(&1, 1010, "example.com"),
          &ReqDnsimple.ZoneRecord.delete(&1, 1010, "example.com", 1)
        ] do
      req = client(404, %{"message" => "missing"}, self(), [{"x-request-id", "missing-record"}])

      assert {:error,
              %ReqDnsimple.Error{
                reason: :not_found,
                metadata: %ReqDnsimple.Metadata{status: 404, request_id: "missing-record"}
              }} = operation.(req)

      assert_received {:request, _request}
      refute_received {:request, _request}
    end
  end

  test "zone-record list_all overloads retain page metadata and the latest budget" do
    pagination = %{
      "current_page" => 1,
      "per_page" => 1,
      "total_entries" => 1,
      "total_pages" => 1
    }

    req =
      client(200, %{"data" => [@record_data], "pagination" => pagination}, self(), [
        {"x-request-id", "records-all"},
        {"etag", "\"records-all\""},
        {"x-ratelimit-remaining", "0"}
      ])

    scoped = ReqDnsimple.for_account(req, 1010)

    page_metadata = %ReqDnsimple.Metadata{
      status: 200,
      pagination: pagination,
      request_id: "records-all",
      etag: "\"records-all\"",
      rate_limit_remaining: 0
    }

    metadata = %ReqDnsimple.Metadata{rate_limit_remaining: 0, pages: [page_metadata]}

    for fetch <- [
          fn -> ReqDnsimple.ZoneRecord.list_all(scoped, "example.com") end,
          fn -> ReqDnsimple.ZoneRecord.list_all(scoped, "example.com", []) end,
          fn -> ReqDnsimple.ZoneRecord.list_all(req, 1010, "example.com") end,
          fn -> ReqDnsimple.ZoneRecord.list_all(req, 1010, "example.com", []) end
        ] do
      assert {:ok, {[%ReqDnsimple.ZoneRecord{id: 1}], ^metadata}} = fetch.()
      assert_request(:get, "/v2/1010/zones/example.com/records", %{"page" => 1}, nil)
      refute_received {:request, _request}
    end
  end

  test "zone-record list validation failures are structured before HTTP through both account forms" do
    req = client(200, %{"data" => []})
    scoped = ReqDnsimple.for_account(req, 1010)

    for operation <- [
          &ReqDnsimple.ZoneRecord.list(req, 1010, "example.com", &1),
          &ReqDnsimple.ZoneRecord.list_page(req, 1010, "example.com", &1),
          &ReqDnsimple.ZoneRecord.list(scoped, "example.com", &1),
          &ReqDnsimple.ZoneRecord.list_page(scoped, "example.com", &1)
        ],
        opts <- [%{}, [unsupported: true], [page: 0], [per_page: 0]] do
      assert {:error,
              %ReqDnsimple.Error{
                reason: %NimbleOptions.ValidationError{},
                metadata: nil
              }} = operation.(opts)
    end

    refute_received {:request, _request}
  end

  test "zone-record page metadata diagnostics do not invalidate resource data" do
    invalid = %{"current_page" => "1"}
    header_errors = %{rate_limit_remaining: {:invalid_header, ["invalid"]}}

    for {fields, invalid_pagination, errors} <- [
          {%{}, nil, header_errors},
          {%{"pagination" => nil}, nil, header_errors},
          {%{"pagination" => invalid}, invalid,
           Map.put(header_errors, :pagination, {:invalid_pagination, invalid})},
          {%{"pagination" => "invalid"}, "invalid",
           Map.put(header_errors, :pagination, {:invalid_pagination, "invalid"})}
        ] do
      req =
        client(200, Map.put(fields, "data", [@record_data]), self(), [
          {"x-request-id", "record-diagnostics"},
          {"x-ratelimit-remaining", "invalid"}
        ])

      metadata = %ReqDnsimple.Metadata{
        status: 200,
        request_id: "record-diagnostics",
        parse_errors: errors
      }

      for operation <- [
            &ReqDnsimple.ZoneRecord.list(&1, 1010, "example.com"),
            &ReqDnsimple.ZoneRecord.list_page(&1, 1010, "example.com")
          ] do
        assert {:ok, {[%ReqDnsimple.ZoneRecord{id: 1, ttl: 0, priority: 0}], ^metadata}} =
                 operation.(req)

        assert_request(:get, "/v2/1010/zones/example.com/records", %{}, nil)
      end

      error_metadata = %{metadata | pages: [metadata]}

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^invalid_pagination},
                metadata: ^error_metadata
              }} = ReqDnsimple.ZoneRecord.list_all(req, 1010, "example.com")

      assert_request(:get, "/v2/1010/zones/example.com/records", %{"page" => 1}, nil)
      refute_received {:request, _request}
    end
  end

  test "create accepts and transmits explicit zero TTL and priority for apex records" do
    attrs = [name: "", type: "MX", content: "mail.example.com", ttl: 0, priority: 0]

    assert {:ok, {%ReqDnsimple.ZoneRecord{ttl: 0, priority: 0}, %ReqDnsimple.Metadata{}}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => @record_data}),
               1010,
               "example.com",
               attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(attrs))
  end

  test "update transmits explicit zero without adding omitted fields" do
    assert {:ok, {%ReqDnsimple.ZoneRecord{ttl: 0, priority: 0}, %ReqDnsimple.Metadata{}}} =
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

    assert {:ok, {%ReqDnsimple.ZoneRecord{id: 1}, %ReqDnsimple.Metadata{}}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => @record_data}),
               1010,
               "example.com",
               create_attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(create_attrs))

    assert {:ok, {%ReqDnsimple.ZoneRecord{id: 1}, %ReqDnsimple.Metadata{}}} =
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

    assert {:ok, {%ReqDnsimple.ZoneRecord{}, %ReqDnsimple.Metadata{}}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => @record_data}),
               1010,
               "example.com",
               create_attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(create_attrs))

    assert {:ok, {%ReqDnsimple.ZoneRecord{}, %ReqDnsimple.Metadata{}}} =
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
      assert {:error,
              %ReqDnsimple.Error{
                reason: %NimbleOptions.ValidationError{key: :integrated_zones},
                metadata: nil
              }} =
               ReqDnsimple.ZoneRecord.create(
                 create_client,
                 1010,
                 "example.com",
                 required ++ [integrated_zones: integrated_zones]
               )

      assert {:error,
              %ReqDnsimple.Error{
                reason: %NimbleOptions.ValidationError{key: :integrated_zones},
                metadata: nil
              }} =
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
    assert {:error,
            %ReqDnsimple.Error{
              reason: %{status: 503, response: %{"message" => "unavailable"}},
              metadata: %ReqDnsimple.Metadata{status: 503}
            }} =
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

    assert {:error,
            %ReqDnsimple.Error{reason: %Req.TransportError{reason: :econnrefused}, metadata: nil}} =
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
      assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
               ReqDnsimple.ZoneRecord.create(
                 create_client,
                 1010,
                 "example.com",
                 invalid_attrs
               )
    end

    update_client = client(200, %{"data" => @record_data})

    for invalid_attrs <- [[ttl: -1], [ttl: "0"], [priority: -1], [priority: "0"]] do
      assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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
    assert {:error, %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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
        assert {:ok, {^distributed, %ReqDnsimple.Metadata{}}} =
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
      for {status, body} <- [
            {401, %{"detail" => "Fake token rejected"}},
            {404, %{"errors" => %{"record" => ["Fake record missing"]}}},
            {504, "Fake gateway timeout"},
            {403, %{"message" => "Fake request forbidden"}},
            {429, %{"message" => "Fake rate limit"}},
            {500, %{"message" => "Fake server failure"}}
          ] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.ZoneRecord.check_distribution(
                   client(status, body),
                   1010,
                   "example.test",
                   1
                 )

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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.ZoneRecord.check_distribution(
                   client(200, body),
                   1010,
                   "example.test",
                   1
                 )
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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
              {%ReqDnsimple.ZoneRecord.BatchResult{
                 creates: [%ReqDnsimple.ZoneRecord{id: 301, parent_id: nil, ttl: 0}],
                 updates: [%ReqDnsimple.ZoneRecord{id: 302, regions: []}],
                 deletes: [%ReqDnsimple.ZoneRecord.DeletedRecord{id: 303}]
               }, %ReqDnsimple.Metadata{}}} =
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
        assert {:ok, {%ReqDnsimple.ZoneRecord.BatchResult{}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.ZoneRecord.batch_change(request, 1010, "example.test", attrs)
      end

      refute_received {:request, _request}
    end

    test "rejects malformed attribute containers before HTTP" do
      request = client(200, %{})

      for malformed <- [[:invalid], [{:name}]] do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %NimbleOptions.ValidationError{
                    message: "expected a keyword list",
                    value: ^malformed
                  },
                  metadata: nil
                }} =
                 ReqDnsimple.ZoneRecord.batch_change(
                   request,
                   1010,
                   "example.test",
                   malformed
                 )
      end

      refute_received {:request, _request}
    end

    test "rejects invalid path parameter types before HTTP" do
      request =
        client(200, %{
          "data" => %{"creates" => [], "updates" => [], "deletes" => []}
        })

      for {account_id, zone_name} <- [
            {"1010", "example.test"},
            {1010, 2020}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.ZoneRecord.batch_change(request, account_id, zone_name, [])
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
              %ReqDnsimple.Error{
                reason: %{
                  status: 400,
                  message: "Fake offline validation failure",
                  errors: errors
                },
                metadata: %ReqDnsimple.Metadata{status: 400}
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 200, response: ^malformed},
                metadata: %ReqDnsimple.Metadata{status: 200}
              }} =
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

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 200, response: ^malformed_timestamp},
                metadata: %ReqDnsimple.Metadata{status: 200}
              }} =
               ReqDnsimple.ZoneRecord.batch_change(
                 client(200, malformed_timestamp),
                 1010,
                 "example.test",
                 []
               )

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.ZoneRecord.batch_change(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 []
               )
    end
  end

  describe "standalone priority compatibility" do
    test "create and root helpers preserve omitted, null, zero, and positive priorities" do
      legacy = client(201, %{"data" => @record_data})
      scoped = ReqDnsimple.for_account(legacy, 1010)

      for create <- [
            &ReqDnsimple.ZoneRecord.create(scoped, "example.com", &1),
            &ReqDnsimple.ZoneRecord.create(legacy, 1010, "example.com", &1),
            &ReqDnsimple.create_zone_record(scoped, "example.com", &1),
            &ReqDnsimple.create_zone_record(legacy, 1010, "example.com", &1)
          ],
          priority_attrs <- [[], [priority: nil], [priority: 0], [priority: 25]] do
        attrs = [name: "", type: "MX", content: "mail.example.com"] ++ priority_attrs

        assert {:ok, {%ReqDnsimple.ZoneRecord{}, %ReqDnsimple.Metadata{}}} = create.(attrs)
        assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(attrs))
      end

      refute_received {:request, _request}
    end

    test "update preserves omitted, null, zero, and positive priorities" do
      legacy = client(200, %{"data" => @record_data})
      scoped = ReqDnsimple.for_account(legacy, 1010)

      for update <- [
            &ReqDnsimple.ZoneRecord.update(scoped, "example.com", 1, &1),
            &ReqDnsimple.ZoneRecord.update(legacy, 1010, "example.com", 1, &1)
          ],
          priority_attrs <- [[], [priority: nil], [priority: 0], [priority: 25]] do
        assert {:ok, {%ReqDnsimple.ZoneRecord{}, %ReqDnsimple.Metadata{}}} =
                 update.(priority_attrs)

        assert_request(
          :patch,
          "/v2/1010/zones/example.com/records/1",
          %{},
          Map.new(priority_attrs)
        )
      end

      refute_received {:request, _request}
    end

    test "invalid priorities and null TTL are rejected before HTTP through every interface" do
      legacy = client(200, %{"data" => @record_data})
      scoped = ReqDnsimple.for_account(legacy, 1010)
      required = [name: "", type: "MX", content: "mail.example.com"]

      invalid_attrs =
        Enum.map([-1, 0.0, 1.5, "0", true, false, :null, [], %{}], &[priority: &1]) ++
          [[ttl: nil]]

      for mutate <- [
            &ReqDnsimple.ZoneRecord.create(scoped, "example.com", required ++ &1),
            &ReqDnsimple.ZoneRecord.create(legacy, 1010, "example.com", required ++ &1),
            &ReqDnsimple.create_zone_record(scoped, "example.com", required ++ &1),
            &ReqDnsimple.create_zone_record(legacy, 1010, "example.com", required ++ &1),
            &ReqDnsimple.ZoneRecord.update(scoped, "example.com", 1, &1),
            &ReqDnsimple.ZoneRecord.update(legacy, 1010, "example.com", 1, &1)
          ],
          attrs <- invalid_attrs do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 mutate.(attrs)
      end

      refute_received {:request, _request}
    end
  end
end
