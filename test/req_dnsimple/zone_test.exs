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

  test "preserves HTTP headers on every zone operation and generic HTTP errors" do
    headers = [
      {"x-request-id", "zone-response"},
      {"x-ratelimit-remaining", "0"},
      {"retry-after", "5"}
    ]

    pagination = %{
      "current_page" => 1,
      "per_page" => 1,
      "total_entries" => 1,
      "total_pages" => 1
    }

    for {operation, body} <- [
          {&ReqDnsimple.Zone.get(&1, 1010, "example.test"), %{"data" => @zone_data}},
          {&ReqDnsimple.Zone.activate(&1, 1010, "example.test"), %{"data" => @zone_data}},
          {&ReqDnsimple.Zone.deactivate(&1, 1010, "example.test"),
           %{"data" => %{@zone_data | "active" => false}}},
          {&ReqDnsimple.Zone.update_ns_records(&1, 1010, "example.test",
             ns_names: ["ns1.example.test"]
           ), %{"data" => [@record_data]}},
          {&ReqDnsimple.Zone.get_zone_file(&1, 1010, "example.test"),
           %{"data" => %{"zone" => "example.test. 3600 IN NS ns1.example.test.\n"}}},
          {&ReqDnsimple.Zone.check_zone_distribution(&1, 1010, "example.test"),
           %{"data" => %{"distributed" => false}}},
          {&ReqDnsimple.Zone.list(&1, 1010),
           %{"data" => [@zone_data], "pagination" => pagination}},
          {&ReqDnsimple.Zone.list_page(&1, 1010),
           %{"data" => [@zone_data], "pagination" => pagination}}
        ] do
      metadata = %ReqDnsimple.Metadata{
        status: 200,
        pagination: Map.get(body, "pagination"),
        request_id: "zone-response",
        rate_limit_remaining: 0,
        retry_after: "5"
      }

      assert {:ok, {data, ^metadata}} = operation.(client(200, body, self(), headers))

      case body do
        %{"data" => %{"zone" => zone_file}} -> assert data == zone_file
        %{"data" => %{"distributed" => distributed}} -> assert data == distributed
        _resource_body -> refute is_nil(data)
      end

      assert_received {:request, _request}

      error_body = %{"message" => "retry later"}
      error_metadata = %{metadata | status: 429, pagination: nil}

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 429, response: ^error_body},
                metadata: ^error_metadata
              }} = operation.(client(429, error_body, self(), headers))

      assert_received {:request, _request}
      refute_received {:request, _request}
    end
  end

  test "mapped zone errors retain the actual response metadata" do
    for {operation, status, reason} <- [
          {&ReqDnsimple.Zone.list(&1, 1010), 404, :not_found},
          {&ReqDnsimple.Zone.list_page(&1, 1010), 404, :not_found},
          {&ReqDnsimple.Zone.get_zone_file(&1, 1010, "example.test"), 401, :unauthorized},
          {&ReqDnsimple.Zone.get_zone_file(&1, 1010, "example.test"), 404, :not_found},
          {&ReqDnsimple.Zone.check_zone_distribution(&1, 1010, "example.test"), 401,
           :unauthorized},
          {&ReqDnsimple.Zone.check_zone_distribution(&1, 1010, "example.test"), 404, :not_found},
          {&ReqDnsimple.Zone.check_zone_distribution(&1, 1010, "example.test"), 504, :timeout}
        ] do
      req =
        client(status, %{"message" => "offline failure"}, self(), [{"x-request-id", "mapped"}])

      assert {:error,
              %ReqDnsimple.Error{
                reason: ^reason,
                metadata: %ReqDnsimple.Metadata{status: ^status, request_id: "mapped"}
              }} = operation.(req)

      assert_received {:request, _request}
      refute_received {:request, _request}
    end
  end

  test "every bang overload returns one page together with metadata" do
    pagination = %{
      "current_page" => 1,
      "per_page" => 1,
      "total_entries" => 2,
      "total_pages" => 2
    }

    req =
      client(200, %{"data" => [@zone_data], "pagination" => pagination}, self(), [
        {"x-request-id", "bang-page"},
        {"x-ratelimit-remaining", "7"}
      ])

    scoped = ReqDnsimple.for_account(req, 1010)

    metadata = %ReqDnsimple.Metadata{
      status: 200,
      pagination: pagination,
      request_id: "bang-page",
      rate_limit_remaining: 7
    }

    for fetch <- [
          fn -> ReqDnsimple.Zone.list!(scoped) end,
          fn -> ReqDnsimple.Zone.list!(scoped, []) end,
          fn -> ReqDnsimple.Zone.list!(req, 1010) end,
          fn -> ReqDnsimple.Zone.list!(req, "1010") end,
          fn -> ReqDnsimple.Zone.list!(req, 1010, []) end
        ] do
      assert {[%ReqDnsimple.Zone{name: "example.test"}], ^metadata} = fetch.()
      assert_request(:get, "/v2/1010/zones", %{}, nil)
      refute_received {:request, _request}
    end
  end

  test "bang failures raise the unified error without losing HTTP or local context" do
    error =
      assert_raise ReqDnsimple.Error, fn ->
        ReqDnsimple.Zone.list!(
          client(404, %{"message" => "missing"}, self(), [{"x-request-id", "bang-error"}]),
          1010
        )
      end

    assert %ReqDnsimple.Error{
             reason: :not_found,
             metadata: %ReqDnsimple.Metadata{status: 404, request_id: "bang-error"}
           } = error

    assert_request(:get, "/v2/1010/zones", %{}, nil)

    req = client(200, %{"data" => []})

    validation_error =
      assert_raise ReqDnsimple.Error, fn ->
        ReqDnsimple.Zone.list!(req, 1010, unsupported: true)
      end

    assert %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil} =
             validation_error

    scope_error = assert_raise ReqDnsimple.Error, fn -> ReqDnsimple.Zone.list!(req) end
    assert %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil} = scope_error
    refute_received {:request, _request}

    test_pid = self()

    req =
      Req.merge(req,
        adapter: fn request ->
          send(test_pid, {:request, request})
          {request, %Req.TransportError{reason: :timeout}}
        end
      )

    transport_error =
      assert_raise ReqDnsimple.Error, fn -> ReqDnsimple.Zone.list!(req, 1010) end

    assert %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil} =
             transport_error

    assert_request(:get, "/v2/1010/zones", %{}, nil)
    refute_received {:request, _request}
  end

  test "zone list_all overloads retain page metadata and clear aggregate response identity" do
    pagination = %{
      "current_page" => 1,
      "per_page" => 1,
      "total_entries" => 1,
      "total_pages" => 1
    }

    req =
      client(200, %{"data" => [@zone_data], "pagination" => pagination}, self(), [
        {"x-request-id", "zone-all"},
        {"etag", "\"zone-all\""},
        {"x-ratelimit-remaining", "0"}
      ])

    scoped = ReqDnsimple.for_account(req, 1010)

    page_metadata = %ReqDnsimple.Metadata{
      status: 200,
      pagination: pagination,
      request_id: "zone-all",
      etag: "\"zone-all\"",
      rate_limit_remaining: 0
    }

    metadata = %ReqDnsimple.Metadata{rate_limit_remaining: 0, pages: [page_metadata]}

    for fetch <- [
          fn -> ReqDnsimple.Zone.list_all(scoped) end,
          fn -> ReqDnsimple.Zone.list_all(scoped, []) end,
          fn -> ReqDnsimple.Zone.list_all(req, 1010) end,
          fn -> ReqDnsimple.Zone.list_all(req, 1010, []) end
        ] do
      assert {:ok, {[%ReqDnsimple.Zone{name: "example.test"}], ^metadata}} = fetch.()
      assert_request(:get, "/v2/1010/zones", %{"page" => 1}, nil)
      refute_received {:request, _request}
    end
  end

  test "zone list validation failures are structured before HTTP through both account forms" do
    req = client(200, %{"data" => []})
    scoped = ReqDnsimple.for_account(req, 1010)

    for operation <- [
          &ReqDnsimple.Zone.list(req, 1010, &1),
          &ReqDnsimple.Zone.list_page(req, 1010, &1),
          &ReqDnsimple.Zone.list(scoped, &1),
          &ReqDnsimple.Zone.list_page(scoped, &1)
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

  test "zone page metadata diagnostics do not invalidate resource data" do
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
        client(200, Map.put(fields, "data", [@zone_data]), self(), [
          {"x-request-id", "diagnostics"},
          {"x-ratelimit-remaining", "invalid"}
        ])

      metadata = %ReqDnsimple.Metadata{
        status: 200,
        request_id: "diagnostics",
        parse_errors: errors
      }

      for operation <- [&ReqDnsimple.Zone.list(&1, 1010), &ReqDnsimple.Zone.list_page(&1, 1010)] do
        assert {:ok, {[%ReqDnsimple.Zone{name: "example.test"}], ^metadata}} = operation.(req)
        assert_request(:get, "/v2/1010/zones", %{}, nil)
      end

      error_metadata = %{metadata | pages: [metadata]}

      assert {:error,
              %ReqDnsimple.Error{
                reason: {:invalid_pagination, ^invalid_pagination},
                metadata: ^error_metadata
              }} = ReqDnsimple.Zone.list_all(req, 1010)

      assert_request(:get, "/v2/1010/zones", %{"page" => 1}, nil)
      refute_received {:request, _request}
    end
  end

  describe "get/3" do
    test "getZone sends one bodyless request and returns the complete typed zone" do
      assert {:ok,
              {%ReqDnsimple.Zone{
                 id: 1,
                 account_id: 1010,
                 name: "example.test",
                 reverse: false,
                 secondary: false,
                 last_transferred_at: nil,
                 active: true,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Zone.get(
                 client(200, %{"data" => @zone_data}),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/zones/example.test", %{}, nil)
      refute_received {:request, _request}
    end

    test "getZone preserves zero, empty, false, and a non-null transfer timestamp" do
      transferred_zone =
        @zone_data
        |> Map.put("active", false)
        |> Map.put("last_transferred_at", "2026-08-31T09:15:00+02:00")

      assert {:ok,
              {%ReqDnsimple.Zone{
                 active: false,
                 reverse: false,
                 secondary: false,
                 last_transferred_at: ~U[2026-08-31 07:15:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Zone.get(
                 client(200, %{"data" => transferred_zone}),
                 0,
                 ""
               )

      assert_request(:get, "/v2/0/zones/", %{}, nil)
      refute_received {:request, _request}
    end

    test "getZone rejects invalid path parameters before HTTP" do
      request = client(200, %{"data" => @zone_data})

      for {account_id, zone} <- [
            {"1010", "example.test"},
            {nil, "example.test"},
            {1010, nil},
            {1010, 42},
            {1010, []}
          ] do
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
                 ReqDnsimple.Zone.get(request, account_id, zone)
      end

      refute_received {:request, _request}
    end

    test "getZone preserves documented and shared HTTP and transport failures" do
      for status <- [401, 403, 404, 429, 500, 418] do
        body = %{
          "message" => "Fake offline request failure",
          "errors" => %{"zone" => ["is unavailable"]}
        }

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
                 ReqDnsimple.Zone.get(client(status, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/zones/example.test", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Zone.get(
                 transport_error_client(:timeout),
                 1010,
                 "example.test"
               )
    end

    test "getZone returns explicit errors for malformed success responses" do
      malformed_bodies = [
        %{},
        %{"data" => nil},
        %{"data" => []},
        %{"data" => Map.delete(@zone_data, "last_transferred_at")},
        %{"data" => Map.delete(@zone_data, "active")},
        %{"data" => Map.put(@zone_data, "id", "1")},
        %{"data" => Map.put(@zone_data, "reverse", nil)},
        %{"data" => Map.put(@zone_data, "last_transferred_at", "not-a-timestamp")},
        %{"data" => Map.put(@zone_data, "created_at", nil)}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Zone.get(client(200, body), 1010, "example.test")

        assert_request(:get, "/v2/1010/zones/example.test", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 201, response: %{"data" => @zone_data}},
                metadata: %ReqDnsimple.Metadata{status: 201}
              }} =
               ReqDnsimple.Zone.get(
                 client(201, %{"data" => @zone_data}),
                 1010,
                 "example.test"
               )

      assert_request(:get, "/v2/1010/zones/example.test", %{}, nil)
      refute_received {:request, _request}
    end
  end

  describe "activate/3" do
    test "activateZoneService sends one bodyless request and returns the active zone" do
      assert {:ok,
              {%ReqDnsimple.Zone{
                 id: 1,
                 account_id: 1010,
                 name: "example.test",
                 reverse: false,
                 secondary: false,
                 last_transferred_at: nil,
                 active: true,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Zone.activate(
                 client(200, %{"data" => @zone_data}),
                 1010,
                 "example.test"
               )

      assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "activateZoneService accepts zero and empty path identifiers" do
      assert {:ok, {%ReqDnsimple.Zone{}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        %{"data" => Map.delete(@zone_data, "active")},
        %{"data" => Map.put(@zone_data, "id", "1")},
        %{"data" => Map.put(@zone_data, "reverse", nil)},
        %{"data" => Map.put(@zone_data, "last_transferred_at", "not-a-timestamp")},
        %{"data" => Map.put(@zone_data, "created_at", nil)}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Zone.activate(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 201, response: %{"data" => @zone_data}},
                metadata: %ReqDnsimple.Metadata{status: 201}
              }} =
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

      assert {:ok,
              {%ReqDnsimple.Zone{last_transferred_at: ~U[2026-08-31 07:15:00Z]},
               %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Zone.activate(
                 client(200, %{"data" => transferred_zone}),
                 1010,
                 "example.test"
               )

      assert_request(:put, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "activateZoneService preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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
              {%ReqDnsimple.Zone{
                 id: 1,
                 account_id: 1010,
                 name: "example.test",
                 reverse: false,
                 secondary: false,
                 last_transferred_at: nil,
                 active: false,
                 created_at: ~U[2026-09-01 08:00:00Z],
                 updated_at: ~U[2026-09-01 08:30:00Z]
               }, %ReqDnsimple.Metadata{}}} =
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

      assert {:ok, {%ReqDnsimple.Zone{active: false}, %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        %{"data" => Map.delete(inactive_zone, "active")},
        %{"data" => Map.put(inactive_zone, "id", "1")},
        %{"data" => Map.put(inactive_zone, "active", nil)},
        %{"data" => Map.put(inactive_zone, "last_transferred_at", "not-a-timestamp")},
        %{"data" => Map.put(inactive_zone, "created_at", nil)}
      ]

      for body <- malformed_bodies do
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
                 ReqDnsimple.Zone.deactivate(
                   client(200, body),
                   1010,
                   "example.test"
                 )

        assert_request(:delete, "/v2/1010/zones/example.test/activation", %{}, nil)
        refute_received {:request, _request}
      end

      assert {:error,
              %ReqDnsimple.Error{
                reason: %{status: 204, response: nil},
                metadata: %ReqDnsimple.Metadata{status: 204}
              }} =
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
              {%ReqDnsimple.Zone{
                 active: false,
                 last_transferred_at: ~U[2026-08-31 07:15:00Z]
               }, %ReqDnsimple.Metadata{}}} =
               ReqDnsimple.Zone.deactivate(
                 client(200, %{"data" => inactive_zone}),
                 1010,
                 "example.test"
               )

      assert_request(:delete, "/v2/1010/zones/example.test/activation", %{}, nil)
      refute_received {:request, _request}
    end

    test "deactivateZoneService preserves transport failures" do
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
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
              {[
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
               ], %ReqDnsimple.Metadata{}}} =
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
        assert {:ok, {[], %ReqDnsimple.Metadata{}}} =
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
        assert {:error,
                %ReqDnsimple.Error{reason: %NimbleOptions.ValidationError{}, metadata: nil}} =
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

        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: ^status, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: ^status}
                }} =
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
        assert {:error,
                %ReqDnsimple.Error{
                  reason: %{status: 200, response: ^body},
                  metadata: %ReqDnsimple.Metadata{status: 200}
                }} =
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
      assert {:error,
              %ReqDnsimple.Error{reason: %Req.TransportError{reason: :timeout}, metadata: nil}} =
               ReqDnsimple.Zone.update_ns_records(
                 transport_error_client(:timeout),
                 1010,
                 "example.test",
                 ns_names: ["ns1.example.test"]
               )
    end
  end
end
