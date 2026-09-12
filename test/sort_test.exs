defmodule ReqDnsimple.SortTest do
  use ExUnit.Case, async: true

  import ReqDnsimple.TestSupport

  test "sort conversion preserves keyword ordering and supports atom shorthand" do
    assert ReqDnsimple.convert_sort_to_string(sort: [name: :desc, id: :asc]) ==
             [sort: "name:desc,id:asc"]

    assert ReqDnsimple.convert_sort_to_string(sort: [:id, name: :desc]) ==
             [sort: "id:asc,name:desc"]

    assert ReqDnsimple.convert_sort_to_string(page: 1) == [page: 1]
  end

  test "list operations accept endpoint-specific fields and render mixed sorts" do
    for {_name, {allowed_fields, operation, response, path}} <- list_operations() do
      sort = [hd(allowed_fields), {List.last(allowed_fields), :desc}]

      assert {:ok, _result} = operation.(client(200, response), sort: sort)

      expected_sort =
        "#{hd(allowed_fields)}:asc,#{List.last(allowed_fields)}:desc"

      assert_request(:get, path, %{"sort" => expected_sort})
    end
  end

  test "list operations reject invalid sort values before making a request" do
    invalid_sorts = [
      "name:asc",
      [nil],
      [nil, name: :sideways],
      [nil, :unsupported],
      [name: :sideways],
      [{:name, :asc, :extra}],
      [{"name", :asc}]
    ]

    for {_name, {_allowed_fields, operation, _response, _path}} <- list_operations(),
        sort <- invalid_sorts do
      assert {:error, %NimbleOptions.ValidationError{key: :sort}} =
               operation.(ReqDnsimple.new_client("dnsimple_u_fake-token"), sort: sort)

      refute_receive {:request, _}
    end
  end

  test "list operations reject fields outside their endpoint allowlist before HTTP" do
    for {_name, {allowed_fields, operation, _response, _path}} <- list_operations() do
      unsupported_field =
        Enum.find([:id, :name, :content, :type, :label, :email, :invoiced], fn field ->
          field not in allowed_fields
        end)

      assert {:error, %NimbleOptions.ValidationError{key: :sort}} =
               operation.(
                 ReqDnsimple.new_client("dnsimple_u_fake-token"),
                 sort: [{unsupported_field, :asc}]
               )

      refute_receive {:request, _}
    end
  end

  defp list_operations do
    [
      zones: {
        [:id, :name],
        fn client, opts -> ReqDnsimple.Zone.list(client, 1010, opts) end,
        %{"data" => []},
        "/v2/1010/zones"
      },
      records: {
        [:id, :name, :content, :type],
        fn client, opts -> ReqDnsimple.ZoneRecord.list(client, 1010, "example.com", opts) end,
        %{"data" => [], "pagination" => %{"current_page" => 1, "total_pages" => 1}},
        "/v2/1010/zones/example.com/records"
      },
      contacts: {
        [:id, :label, :email],
        fn client, opts -> ReqDnsimple.Contact.list(client, 1010, opts) end,
        %{"data" => []},
        "/v2/1010/contacts"
      },
      charges: {
        [:invoiced],
        fn client, opts -> ReqDnsimple.BillingCharge.list(client, 1010, opts) end,
        %{"data" => []},
        "/v2/1010/billing/charges"
      }
    ]
  end
end
