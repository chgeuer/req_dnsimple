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
end
