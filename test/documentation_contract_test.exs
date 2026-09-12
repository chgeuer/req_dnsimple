defmodule ReqDnsimple.DocumentationContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @implementation_states ~w(existing implemented pending out-of-scope)

  test "public guides describe bounded coverage and the versioned inventory states" do
    readme = File.read!(Path.join(@root, "README.md"))
    usage_rules = File.read!(Path.join(@root, "usage-rules.md"))
    inventory = File.read!(Path.join(@root, "docs/audit/operation-inventory.json"))

    refute readme =~ "all DNSimple API operations"
    refute usage_rules =~ "all DNSimple API operations"

    assert readme =~ "docs/audit/operation-inventory.json"
    assert usage_rules =~ "docs/audit/operation-inventory.json"

    for state <- @implementation_states do
      assert readme =~ "`#{state}`"
      assert usage_rules =~ "`#{state}`"
    end

    assert_inventory_states(inventory)
  end

  test "inventory accepts completed scoped coverage with no pending operations" do
    inventory = inventory_with_replaced_state("pending", "implemented")

    refute Enum.any?(Jason.decode!(inventory)["operations"], &(&1["implementation"] == "pending"))
    assert_inventory_states(inventory)
  end

  test "inventory accepts a campaign before its first new operation is implemented" do
    inventory = inventory_with_replaced_state("implemented", "pending")

    refute Enum.any?(
             Jason.decode!(inventory)["operations"],
             &(&1["implementation"] == "implemented")
           )

    assert_inventory_states(inventory)
  end

  test "inventory rejects missing, unknown, and incorrectly typed implementation states" do
    valid_operations = Enum.map(@implementation_states, &%{"implementation" => &1})

    for invalid_operation <- [
          %{},
          %{"implementation" => nil},
          %{"implementation" => "unknown"},
          %{"implementation" => 123}
        ] do
      inventory =
        Jason.encode!(%{"operations" => valid_operations ++ [invalid_operation]}, pretty: true)

      assert_raise ExUnit.AssertionError, fn ->
        assert_inventory_states(inventory)
      end
    end
  end

  test "functions used by the public examples are exported" do
    exports = [
      {ReqDnsimple, :new_client, 1},
      {ReqDnsimple, :whoami, 1},
      {ReqDnsimple, :ns_records, 3},
      {ReqDnsimple.Zone, :list, 3},
      {ReqDnsimple.Zone, :list_page, 3},
      {ReqDnsimple.Zone, :list_all, 3},
      {ReqDnsimple.ZoneRecord, :list, 4},
      {ReqDnsimple.ZoneRecord, :list_page, 4},
      {ReqDnsimple.ZoneRecord, :list_all, 4},
      {ReqDnsimple.ZoneRecord, :create, 4},
      {ReqDnsimple.ZoneRecord, :update, 5},
      {ReqDnsimple.ZoneRecord, :delete, 4},
      {ReqDnsimple.ZoneRecord, :batch_change, 4},
      {ReqDnsimple.BillingCharge, :list, 3},
      {ReqDnsimple.Contact, :list, 3},
      {ReqDnsimple.Contact, :get, 3},
      {ReqDnsimple.Contact, :delete, 3},
      {ReqDnsimple.PrimaryServer, :get, 3},
      {ReqDnsimple.PrimaryServer, :delete, 3}
    ]

    for {module, function, arity} <- exports do
      assert Code.ensure_loaded?(module), "expected #{inspect(module)} to load"

      assert function_exported?(module, function, arity),
             "expected #{inspect(module)}.#{function}/#{arity} to be exported"
    end
  end

  defp inventory_with_replaced_state(from, to) do
    inventory =
      @root
      |> Path.join("docs/audit/operation-inventory.json")
      |> File.read!()
      |> Jason.decode!()

    operations =
      Enum.map(inventory["operations"], fn
        %{"implementation" => ^from} = operation -> Map.put(operation, "implementation", to)
        operation -> operation
      end)

    inventory
    |> Map.put("operations", operations)
    |> Jason.encode!(pretty: true)
  end

  defp assert_inventory_states(inventory) do
    assert %{"operations" => operations} = Jason.decode!(inventory)
    assert is_list(operations) and operations != []

    for operation <- operations do
      assert is_map(operation)
      assert operation["implementation"] in @implementation_states
    end
  end
end
