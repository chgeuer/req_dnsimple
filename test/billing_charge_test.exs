defmodule ReqDnsimple.BillingChargeTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  test "list preserves exact monetary strings and nullable manual item references" do
    body = %{
      "data" => [
        %{
          "balance_amount" => "12345678901234567890.1200",
          "invoiced_at" => "2024-01-02T03:04:05Z",
          "items" => [
            %{
              "amount" => "99999999999999999999.9900",
              "description" => "Manual adjustment",
              "product_id" => nil,
              "product_reference" => nil,
              "product_type" => "manual"
            }
          ],
          "reference" => "INV-1",
          "state" => "collected",
          "total_amount" => "100000000000000000000.1100"
        }
      ]
    }

    assert {:ok,
            {[
               %ReqDnsimple.BillingCharge{
                 balance_amount: "12345678901234567890.1200",
                 items: [
                   %ReqDnsimple.BillingCharge.Item{
                     amount: "99999999999999999999.9900",
                     product_id: nil,
                     product_reference: nil
                   }
                 ],
                 total_amount: "100000000000000000000.1100"
               }
             ], %ReqDnsimple.Metadata{status: 200}}} =
             ReqDnsimple.BillingCharge.list(client(200, body), 1010)

    assert_request(:get, "/v2/1010/billing/charges")
  end

  test "public types describe monetary strings and nullable manual item references" do
    charge_type = rendered_type(ReqDnsimple.BillingCharge)
    item_type = rendered_type(ReqDnsimple.BillingCharge.Item)

    assert charge_type =~ "balance_amount: String.t()"
    assert charge_type =~ "total_amount: String.t()"
    assert item_type =~ "amount: String.t()"
    assert item_type =~ "product_id: integer() | nil"
    assert item_type =~ "product_reference: String.t() | nil"
  end

  defp rendered_type(module) do
    {:ok, types} = Code.Typespec.fetch_types(module)
    {:type, type} = List.keyfind(types, :type, 0)

    type
    |> Code.Typespec.type_to_quoted()
    |> Macro.to_string()
  end
end
