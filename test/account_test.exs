defmodule ReqDnsimple.AccountTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  @account_data %{
    "id" => 1010,
    "email" => "owner@example.com",
    "name" => "Example Team",
    "plan_identifier" => "teams-v1-monthly",
    "created_at" => "2024-01-01T00:00:00Z",
    "updated_at" => "2024-01-02T00:00:00Z"
  }

  test "list preserves the optional account name and its existing bare-list response" do
    assert [account] =
             ReqDnsimple.Account.list(client(200, %{"data" => [@account_data]}))

    assert %ReqDnsimple.Account{
             id: 1010,
             email: "owner@example.com",
             plan_identifier: "teams-v1-monthly",
             created_at: ~U[2024-01-01 00:00:00Z],
             updated_at: ~U[2024-01-02 00:00:00Z]
           } = account

    assert Map.fetch(account, :name) == {:ok, "Example Team"}
    assert_request(:get, "/v2/accounts")
  end

  test "from_json accepts missing and null account names" do
    account_without_name = Map.delete(@account_data, "name")
    account_with_null_name = Map.put(@account_data, "name", nil)

    assert {:ok, nil} =
             account_without_name
             |> ReqDnsimple.Account.from_json()
             |> Map.fetch(:name)

    assert {:ok, nil} =
             account_with_null_name
             |> ReqDnsimple.Account.from_json()
             |> Map.fetch(:name)
  end
end
