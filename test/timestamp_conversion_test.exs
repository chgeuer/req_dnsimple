defmodule ReqDnsimple.TimestampConversionTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  alias ReqDnsimple.Metadata

  test "normalizes valid response timestamps across resource types" do
    assert {:ok,
            {[%ReqDnsimple.Account{created_at: ~U[2024-01-01 00:00:00Z]}], %Metadata{status: 200}}} =
             ReqDnsimple.Account.list(
               client(200, %{"data" => [%{"created_at" => "2024-01-01T00:00:00Z"}]})
             )

    assert_request(:get, "/v2/accounts")

    assert {:ok,
            {[
               %ReqDnsimple.Zone{
                 created_at: ~U[2024-01-01 05:30:00Z],
                 updated_at: ~U[2024-01-02 00:34:05.123456Z],
                 last_transferred_at: nil
               }
             ], %Metadata{status: 200}}} =
             ReqDnsimple.Zone.list(
               client(200, %{
                 "data" => [
                   %{
                     "created_at" => "2024-01-01T00:00:00-05:30",
                     "updated_at" => "2024-01-02T03:04:05.123456+02:30",
                     "last_transferred_at" => nil
                   }
                 ]
               }),
               1010
             )

    assert_request(:get, "/v2/1010/zones")

    assert {:ok,
            {[
               %ReqDnsimple.ZoneRecord{
                 created_at: ~U[2023-12-31 22:00:00Z],
                 updated_at: ~U[2024-01-02 08:00:00Z]
               }
             ],
             %Metadata{
               status: 200,
               pagination: nil,
               parse_errors: %{pagination: {:invalid_pagination, %{"current_page" => 1}}}
             }}} =
             ReqDnsimple.ZoneRecord.list(
               client(200, %{
                 "data" => [
                   %{
                     "created_at" => "2024-01-01T00:00:00+02:00",
                     "updated_at" => "2024-01-02T00:00:00-08:00"
                   }
                 ],
                 "pagination" => %{"current_page" => 1}
               }),
               1010,
               "example.com"
             )

    assert_request(:get, "/v2/1010/zones/example.com/records")

    assert {:ok,
            {%ReqDnsimple.Contact{
               created_at: ~U[2024-01-01 00:00:00.250Z],
               updated_at: ~U[2024-01-01 00:00:00Z]
             }, %Metadata{status: 200}}} =
             ReqDnsimple.Contact.get(
               client(200, %{
                 "data" => %{
                   "created_at" => "2024-01-01T00:00:00.250Z",
                   "updated_at" => "2024-01-01T01:00:00+01:00"
                 }
               }),
               1010,
               42
             )

    assert_request(:get, "/v2/1010/contacts/42")

    assert {:ok,
            {[%ReqDnsimple.BillingCharge{invoiced_at: ~U[2024-01-01 08:00:00Z]}],
             %Metadata{status: 200}}} =
             ReqDnsimple.BillingCharge.list(
               client(200, %{
                 "data" => [%{"invoiced_at" => "2024-01-01T00:00:00-08:00", "items" => []}]
               }),
               1010
             )

    assert_request(:get, "/v2/1010/billing/charges")
  end

  test "retains missing and null timestamps" do
    assert %ReqDnsimple.Account{created_at: nil, updated_at: nil} =
             ReqDnsimple.Account.from_json(%{"created_at" => nil})
  end

  test "raises for malformed timestamps" do
    assert_raise MatchError, fn ->
      ReqDnsimple.Account.from_json(%{"created_at" => "not-a-timestamp"})
    end
  end
end
