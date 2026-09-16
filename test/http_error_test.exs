defmodule ReqDnsimple.HttpErrorTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  alias ReqDnsimple.{Error, Metadata}

  @generic_body %{"message" => "request failed"}
  @response_headers [
    {"x-ratelimit-limit", "1200"},
    {"x-ratelimit-remaining", "17"},
    {"x-ratelimit-reset", "1790000000"},
    {"x-request-id", "shared-http-response"},
    {"etag", ~s("http-response")},
    {"retry-after", "60"}
  ]
  @response_metadata %Metadata{
    rate_limit: 1200,
    rate_limit_remaining: 17,
    rate_limit_reset: 1_790_000_000,
    request_id: "shared-http-response",
    etag: ~s("http-response"),
    retry_after: "60"
  }

  test "unmocked requests fail closed" do
    assert_raise RuntimeError, ~r/unexpected unmocked HTTP request/, fn ->
      ReqDnsimple.Account.list(ReqDnsimple.new_client("dnsimple_u_fake-token"))
    end
  end

  test "every existing wrapper returns generic HTTP reasons with response metadata" do
    for {name, status, operation} <- existing_operations() do
      page_metadata = %Metadata{@response_metadata | status: status}

      metadata =
        if name == "NS records" do
          %Metadata{page_metadata | pages: [page_metadata]}
        else
          page_metadata
        end

      assert operation.(client(status, @generic_body, self(), @response_headers)) ==
               {:error,
                %Error{
                  reason: %{status: status, response: @generic_body},
                  metadata: metadata
                }},
             "#{name} did not preserve the HTTP reason and metadata"
    end
  end

  test "specific HTTP error reasons remain unchanged and retain response metadata" do
    assert ReqDnsimple.Zone.list(
             client(404, @generic_body, self(), @response_headers),
             1010
           ) ==
             {:error,
              %Error{
                reason: :not_found,
                metadata: %Metadata{@response_metadata | status: 404}
              }}

    for operation <- [
          &ReqDnsimple.Zone.get_zone_file(&1, 1010, "example.com"),
          &ReqDnsimple.Zone.check_zone_distribution(&1, 1010, "example.com")
        ] do
      assert operation.(client(401, @generic_body, self(), @response_headers)) ==
               {:error,
                %Error{
                  reason: :unauthorized,
                  metadata: %Metadata{@response_metadata | status: 401}
                }}

      assert operation.(client(404, @generic_body, self(), @response_headers)) ==
               {:error,
                %Error{
                  reason: :not_found,
                  metadata: %Metadata{@response_metadata | status: 404}
                }}
    end

    assert ReqDnsimple.Zone.check_zone_distribution(
             client(504, @generic_body, self(), @response_headers),
             1010,
             "example.com"
           ) ==
             {:error,
              %Error{
                reason: :timeout,
                metadata: %Metadata{@response_metadata | status: 504}
              }}

    for operation <- [
          &ReqDnsimple.ZoneRecord.list(&1, 1010, "example.com"),
          &ReqDnsimple.ZoneRecord.get(&1, 1010, "example.com", 42),
          &ReqDnsimple.ZoneRecord.create(&1, 1010, "example.com",
            name: "www",
            type: "A",
            content: "192.0.2.1"
          ),
          &ReqDnsimple.ZoneRecord.update(&1, 1010, "example.com", 42, content: "192.0.2.2"),
          &ReqDnsimple.ZoneRecord.delete(&1, 1010, "example.com", 42)
        ] do
      assert operation.(client(404, @generic_body, self(), @response_headers)) ==
               {:error,
                %Error{
                  reason: :not_found,
                  metadata: %Metadata{@response_metadata | status: 404}
                }}
    end

    validation_body = %{
      "message" => "Validation failed",
      "errors" => %{"content" => ["is invalid"]}
    }

    for operation <- [
          &ReqDnsimple.ZoneRecord.create(&1, 1010, "example.com",
            name: "www",
            type: "A",
            content: "invalid"
          ),
          &ReqDnsimple.ZoneRecord.update(&1, 1010, "example.com", 42, content: "invalid")
        ] do
      assert operation.(client(400, validation_body, self(), @response_headers)) ==
               {:error,
                %Error{
                  reason: %{
                    status: 400,
                    message: "Validation failed",
                    errors: %{"content" => ["is invalid"]}
                  },
                  metadata: %Metadata{@response_metadata | status: 400}
                }}
    end
  end

  test "every existing wrapper returns structured transport errors without HTTP metadata" do
    for {name, _status, operation} <- existing_operations() do
      assert {:error,
              %Error{
                reason: %Req.TransportError{reason: :econnrefused},
                metadata: nil
              }} =
               operation.(transport_error_client(:econnrefused)),
             "#{name} did not preserve the transport error"
    end
  end

  test "successful wrappers return typed data with metadata and preserve request contracts" do
    account_data = %{
      "id" => 1010,
      "email" => "owner@example.com",
      "plan_identifier" => "dnsimple",
      "created_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-02T00:00:00Z"
    }

    assert {:ok, {[%ReqDnsimple.Account{id: 1010}], %Metadata{status: 200}}} =
             ReqDnsimple.Account.list(client(200, %{"data" => [account_data]}))

    assert_request(:get, "/v2/accounts")

    assert {:ok, {{:user, %{"id" => 7}}, %Metadata{status: 200}}} =
             ReqDnsimple.whoami(
               client(200, %{"data" => %{"user" => %{"id" => 7}, "account" => nil}})
             )

    assert_request(:get, "/v2/whoami")

    ns_data = %{
      "id" => 1,
      "zone_id" => "example.com",
      "parent_id" => nil,
      "name" => "",
      "content" => "ns1.dnsimple.com",
      "ttl" => 3600,
      "priority" => nil,
      "type" => "NS",
      "regions" => ["global"],
      "system_record" => true,
      "created_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-02T00:00:00Z"
    }

    ns_pagination = %{
      "current_page" => 1,
      "per_page" => 100,
      "total_entries" => 1,
      "total_pages" => 1
    }

    assert {:ok,
            {[%ReqDnsimple.NsRecord{id: 1}],
             %Metadata{
               status: nil,
               pagination: nil,
               request_id: nil,
               etag: nil,
               pages: [%Metadata{status: 200, pagination: ^ns_pagination}]
             }}} =
             ReqDnsimple.ns_records(
               client(200, %{"data" => [ns_data], "pagination" => ns_pagination}),
               1010,
               "example.com"
             )

    assert_request(:get, "/v2/1010/zones/example.com/records", %{
      "name" => "",
      "type" => "NS",
      "page" => 1
    })

    zone_data = %{
      "id" => 9,
      "account_id" => 1010,
      "name" => "example.com",
      "active" => true,
      "reverse" => false,
      "secondary" => false,
      "created_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-02T00:00:00Z",
      "last_transferred_at" => nil
    }

    assert {:ok, {[%ReqDnsimple.Zone{id: 9}], %Metadata{status: 200}}} =
             ReqDnsimple.Zone.list(client(200, %{"data" => [zone_data]}), 1010,
               name_like: "example",
               page: 2
             )

    assert_request(:get, "/v2/1010/zones", %{"name_like" => "example", "page" => 2})

    assert {:ok, {"$ORIGIN example.com.", %Metadata{status: 200}}} =
             ReqDnsimple.Zone.get_zone_file(
               client(200, %{"data" => %{"zone" => "$ORIGIN example.com."}}),
               1010,
               "example.com"
             )

    assert_request(:get, "/v2/1010/zones/example.com/file")

    assert {:ok, {true, %Metadata{status: 200}}} =
             ReqDnsimple.Zone.check_zone_distribution(
               client(200, %{"data" => %{"distributed" => true}}),
               1010,
               "example.com"
             )

    assert_request(:get, "/v2/1010/zones/example.com/distribution")

    record_data = Map.put(ns_data, "type", "A") |> Map.put("content", "192.0.2.1")
    pagination = %{"current_page" => 1, "total_pages" => 1}

    assert {:ok,
            {[%ReqDnsimple.ZoneRecord{id: 1}],
             %Metadata{
               status: 200,
               pagination: nil,
               parse_errors: %{pagination: {:invalid_pagination, ^pagination}}
             }}} =
             ReqDnsimple.ZoneRecord.list(
               client(200, %{"data" => [record_data], "pagination" => pagination}),
               1010,
               "example.com",
               type: "A",
               per_page: 25
             )

    assert_request(:get, "/v2/1010/zones/example.com/records", %{
      "type" => "A",
      "per_page" => 25
    })

    assert {:ok, {%ReqDnsimple.ZoneRecord{id: 1}, %Metadata{status: 200}}} =
             ReqDnsimple.ZoneRecord.get(
               client(200, %{"data" => record_data}),
               1010,
               "example.com",
               1
             )

    assert_request(:get, "/v2/1010/zones/example.com/records/1")

    create_attrs = [name: "www", type: "A", content: "192.0.2.1", ttl: 3600]

    assert {:ok, {%ReqDnsimple.ZoneRecord{id: 1}, %Metadata{status: 201}}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => record_data}),
               1010,
               "example.com",
               create_attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(create_attrs))

    assert {:ok, {%ReqDnsimple.ZoneRecord{id: 1}, %Metadata{status: 200}}} =
             ReqDnsimple.ZoneRecord.update(
               client(200, %{"data" => record_data}),
               1010,
               "example.com",
               1,
               content: "192.0.2.1"
             )

    assert_request(
      :patch,
      "/v2/1010/zones/example.com/records/1",
      %{},
      %{content: "192.0.2.1"}
    )

    assert {:ok, {nil, %Metadata{status: 204}}} =
             ReqDnsimple.ZoneRecord.delete(client(204, nil), 1010, "example.com", 1)

    assert_request(:delete, "/v2/1010/zones/example.com/records/1")

    contact_data = %{
      "id" => 42,
      "account_id" => 1010,
      "first_name" => "Test",
      "last_name" => "User",
      "created_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-02T00:00:00Z"
    }

    assert {:ok, {[%ReqDnsimple.Contact{id: 42}], %Metadata{status: 200}}} =
             ReqDnsimple.Contact.list(
               client(200, %{"data" => [contact_data]}),
               1010,
               page: 2
             )

    assert_request(:get, "/v2/1010/contacts", %{"page" => 2})

    assert {:ok, {%ReqDnsimple.Contact{id: 42}, %Metadata{status: 200}}} =
             ReqDnsimple.Contact.get(client(200, %{"data" => contact_data}), 1010, 42)

    assert_request(:get, "/v2/1010/contacts/42")

    charge_data = %{
      "balance_amount" => "1.00",
      "items" => [],
      "reference" => "INV-1",
      "state" => "collected",
      "total_amount" => "1.00",
      "invoiced_at" => "2024-01-01T00:00:00Z"
    }

    assert {:ok, {[%ReqDnsimple.BillingCharge{reference: "INV-1"}], %Metadata{status: 200}}} =
             ReqDnsimple.BillingCharge.list(
               client(200, %{"data" => [charge_data]}),
               1010,
               start_date: "2024-01-01"
             )

    assert_request(:get, "/v2/1010/billing/charges", %{"start_date" => "2024-01-01"})
  end

  defp existing_operations do
    [
      {"whoami", 400, &ReqDnsimple.whoami/1},
      {"NS records", 401, &ReqDnsimple.ns_records(&1, 1010, "example.com")},
      {"accounts", 402, &ReqDnsimple.Account.list/1},
      {"zones", 403, &ReqDnsimple.Zone.list(&1, 1010)},
      {"zone file", 412, &ReqDnsimple.Zone.get_zone_file(&1, 1010, "example.com")},
      {"zone distribution", 428,
       &ReqDnsimple.Zone.check_zone_distribution(&1, 1010, "example.com")},
      {"zone records", 429, &ReqDnsimple.ZoneRecord.list(&1, 1010, "example.com")},
      {"zone record", 500, &ReqDnsimple.ZoneRecord.get(&1, 1010, "example.com", 42)},
      {"create zone record", 502,
       &ReqDnsimple.ZoneRecord.create(&1, 1010, "example.com",
         name: "www",
         type: "A",
         content: "192.0.2.1"
       )},
      {"update zone record", 503,
       &ReqDnsimple.ZoneRecord.update(&1, 1010, "example.com", 42, content: "192.0.2.2")},
      {"delete zone record", 504, &ReqDnsimple.ZoneRecord.delete(&1, 1010, "example.com", 42)},
      {"contacts", 400, &ReqDnsimple.Contact.list(&1, 1010)},
      {"contact", 401, &ReqDnsimple.Contact.get(&1, 1010, 42)},
      {"billing charges", 500, &ReqDnsimple.BillingCharge.list(&1, 1010)}
    ]
  end
end
