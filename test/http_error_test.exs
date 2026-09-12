defmodule ReqDnsimple.HttpErrorTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @generic_body %{"message" => "request failed"}

  test "unmocked requests fail closed" do
    assert_raise RuntimeError, ~r/unexpected unmocked HTTP request/, fn ->
      ReqDnsimple.Account.list(ReqDnsimple.new_client("dnsimple_u_fake-token"))
    end
  end

  test "every existing wrapper returns explicit generic HTTP errors" do
    operations = [
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

    for {name, status, operation} <- operations do
      assert operation.(client(status, @generic_body)) ==
               {:error, %{status: status, response: @generic_body}},
             "#{name} did not preserve the HTTP status and response body"
    end
  end

  test "existing specific HTTP error mappings remain unchanged" do
    assert ReqDnsimple.Zone.list(client(404, @generic_body), 1010) == {:error, :not_found}

    for operation <- [
          &ReqDnsimple.Zone.get_zone_file(&1, 1010, "example.com"),
          &ReqDnsimple.Zone.check_zone_distribution(&1, 1010, "example.com")
        ] do
      assert operation.(client(401, @generic_body)) == {:error, :unauthorized}
      assert operation.(client(404, @generic_body)) == {:error, :not_found}
    end

    assert ReqDnsimple.Zone.check_zone_distribution(
             client(504, @generic_body),
             1010,
             "example.com"
           ) == {:error, :timeout}

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
      assert operation.(client(404, @generic_body)) == {:error, :not_found}
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
      assert operation.(client(400, validation_body)) ==
               {:error,
                %{
                  status: 400,
                  message: "Validation failed",
                  errors: %{"content" => ["is invalid"]}
                }}
    end
  end

  test "transport errors remain unchanged" do
    client = transport_error_client(:econnrefused)

    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             ReqDnsimple.Account.list(client)
  end

  test "successful wrappers preserve return shapes and request contracts" do
    account_data = %{
      "id" => 1010,
      "email" => "owner@example.com",
      "plan_identifier" => "dnsimple",
      "created_at" => "2024-01-01T00:00:00Z",
      "updated_at" => "2024-01-02T00:00:00Z"
    }

    assert [%ReqDnsimple.Account{id: 1010}] =
             ReqDnsimple.Account.list(client(200, %{"data" => [account_data]}))

    assert_request(:get, "/v2/accounts")

    assert {:user, %{"id" => 7}} =
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

    assert [%ReqDnsimple.NsRecord{id: 1}] =
             ReqDnsimple.ns_records(client(200, %{"data" => [ns_data]}), 1010, "example.com")

    assert_request(:get, "/v2/1010/zones/example.com/ns_records")

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

    assert {:ok, [%ReqDnsimple.Zone{id: 9}]} =
             ReqDnsimple.Zone.list(client(200, %{"data" => [zone_data]}), 1010,
               name_like: "example",
               page: 2
             )

    assert_request(:get, "/v2/1010/zones", %{"name_like" => "example", "page" => 2})

    assert {:ok, "$ORIGIN example.com."} =
             ReqDnsimple.Zone.get_zone_file(
               client(200, %{"data" => %{"zone" => "$ORIGIN example.com."}}),
               1010,
               "example.com"
             )

    assert_request(:get, "/v2/1010/zones/example.com/file")

    assert {:ok, true} =
             ReqDnsimple.Zone.check_zone_distribution(
               client(200, %{"data" => %{"distributed" => true}}),
               1010,
               "example.com"
             )

    assert_request(:get, "/v2/1010/zones/example.com/distribution")

    record_data = Map.put(ns_data, "type", "A") |> Map.put("content", "192.0.2.1")
    pagination = %{"current_page" => 1, "total_pages" => 1}

    assert {:ok, {[%ReqDnsimple.ZoneRecord{id: 1}], ^pagination}} =
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

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 1}} =
             ReqDnsimple.ZoneRecord.get(
               client(200, %{"data" => record_data}),
               1010,
               "example.com",
               1
             )

    assert_request(:get, "/v2/1010/zones/example.com/records/1")

    create_attrs = [name: "www", type: "A", content: "192.0.2.1", ttl: 3600]

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 1}} =
             ReqDnsimple.ZoneRecord.create(
               client(201, %{"data" => record_data}),
               1010,
               "example.com",
               create_attrs
             )

    assert_request(:post, "/v2/1010/zones/example.com/records", %{}, Map.new(create_attrs))

    assert {:ok, %ReqDnsimple.ZoneRecord{id: 1}} =
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

    assert :ok =
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

    assert {:ok, [%ReqDnsimple.Contact{id: 42}]} =
             ReqDnsimple.Contact.list(
               client(200, %{"data" => [contact_data]}),
               1010,
               page: 2
             )

    assert_request(:get, "/v2/1010/contacts", %{"page" => 2})

    assert {:ok, %ReqDnsimple.Contact{id: 42}} =
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

    assert {:ok, [%ReqDnsimple.BillingCharge{reference: "INV-1"}]} =
             ReqDnsimple.BillingCharge.list(
               client(200, %{"data" => [charge_data]}),
               1010,
               start_date: "2024-01-01"
             )

    assert_request(:get, "/v2/1010/billing/charges", %{"start_date" => "2024-01-01"})
  end
end
