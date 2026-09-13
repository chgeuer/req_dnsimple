defmodule ReqDnsimple.DocumentationContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @implementation_states ~w(existing implemented pending out-of-scope)
  @out_of_scope_operation_ids ~w(
    cancelDomainTransfer
    changeDomainDelegationFromVanity
    changeDomainDelegationToVanity
    checkRegistrantChange
    getDomainRegistration
    getDomainRenewal
    getDomainRestore
    getDomainTransfer
  )
  @catalog_modules ~w(
    ReqDnsimple.Certificate
    ReqDnsimple.DnsAnalytics
    ReqDnsimple.Dnssec
    ReqDnsimple.RegistrantChange
    ReqDnsimple.Template
    ReqDnsimple.TemplateRecord
    ReqDnsimple.Webhook
  )
  @collection_interfaces %{
    "ReqDnsimple.BillingCharge" =>
      ~w(list/2 list/3 list_page/2 list_page/3 list_all/2 list_all/3),
    "ReqDnsimple.Contact" => ~w(list/2 list/3 list_page/2 list_page/3 list_all/2 list_all/3),
    "ReqDnsimple.EmailForward" => ~w(list/3 list/4 list_page/3 list_page/4 list_all/3 list_all/4),
    "ReqDnsimple.Zone" => ~w(list/2 list/3 list_page/2 list_page/3 list_all/2 list_all/3),
    "ReqDnsimple.ZoneRecord" => ~w(list/3 list/4 list_page/3 list_page/4 list_all/3 list_all/4)
  }

  test "public guides describe bounded coverage and the versioned inventory states" do
    readme = File.read!(Path.join(@root, "README.md"))
    usage_rules = File.read!(Path.join(@root, "usage-rules.md"))
    inventory = File.read!(Path.join(@root, "docs/audit/operation-inventory.json"))

    refute readme =~ "all DNSimple API operations"
    refute usage_rules =~ "all DNSimple API operations"

    assert readme =~ "docs/audit/operation-inventory.json"
    assert usage_rules =~ "docs/audit/operation-inventory.json"
    assert readme =~ "103 supported operations"
    assert usage_rules =~ "103 supported operations"
    assert readme =~ "eight additional"
    assert usage_rules =~ "eight additional"

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

  test "inventory reconciles every scoped operation with implementation and contract evidence" do
    inventory =
      @root
      |> Path.join("docs/audit/operation-inventory.json")
      |> File.read!()
      |> Jason.decode!()

    assert inventory["approved_operation_count"] == 103
    assert length(inventory["operations"]) == 111

    {scoped, excluded} = Enum.split_with(inventory["operations"], & &1["in_scope"])

    assert length(scoped) == 103
    assert length(excluded) == 8
    assert Enum.uniq_by(inventory["operations"], & &1["operation_id"]) == inventory["operations"]

    assert excluded |> Enum.map(& &1["operation_id"]) |> Enum.sort() ==
             Enum.sort(@out_of_scope_operation_ids)

    for operation <- scoped do
      assert operation["implementation"] in ~w(existing implemented)
      assert operation["implemented_interfaces"] != []
      assert operation["contract_tests"] != []

      for interface <- operation["implemented_interfaces"] do
        assert_exported_interface(interface, operation["operation_id"])
      end

      for contract_test <- operation["contract_tests"] do
        assert_contract_test_location(contract_test, operation["operation_id"])
      end
    end

    for operation <- excluded do
      assert operation["implementation"] == "out-of-scope"
      assert operation["implemented_interfaces"] == []
      assert operation["contract_tests"] == []
    end
  end

  test "public guides catalog supported modules and collection interfaces" do
    readme = File.read!(Path.join(@root, "README.md"))
    usage_rules = File.read!(Path.join(@root, "usage-rules.md"))

    for module <- @catalog_modules do
      assert readme =~ "| `#{module}` |", "README API catalog omits #{module}"
    end

    for {module, interfaces} <- @collection_interfaces do
      readme_row = readme_catalog_row(readme, module)
      short_module = String.replace_prefix(module, "ReqDnsimple.", "")

      for interface <- interfaces do
        assert interface_documented?(readme_row, nil, interface),
               "README API catalog omits #{module}.#{interface}"

        assert interface_documented?(usage_rules, short_module, interface),
               "usage rules omit #{module}.#{interface}"
      end
    end
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
      {ReqDnsimple.Registrar, :disable_auto_renewal, 3},
      {ReqDnsimple.PrimaryServer, :get, 3},
      {ReqDnsimple.PrimaryServer, :list, 3},
      {ReqDnsimple.PrimaryServer, :list_page, 3},
      {ReqDnsimple.PrimaryServer, :list_all, 3},
      {ReqDnsimple.PrimaryServer, :unlink, 4},
      {ReqDnsimple.PrimaryServer, :delete, 3},
      {ReqDnsimple.SecondaryZone, :create, 3}
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

  defp assert_exported_interface(interface, operation_id) do
    {module_name, function_name, arity} =
      case interface do
        %{"module" => module, "function" => function, "arity" => arity} ->
          {module, function, arity}

        interface when is_binary(interface) ->
          [module_and_function, arity] = String.split(interface, "/")
          parts = String.split(module_and_function, ".")
          {Enum.join(Enum.drop(parts, -1), "."), List.last(parts), String.to_integer(arity)}
      end

    module = Module.concat(String.split(module_name, "."))

    assert Code.ensure_loaded?(module),
           "#{operation_id} references unavailable module #{module_name}"

    function = String.to_existing_atom(function_name)

    assert function_exported?(module, function, arity),
           "#{operation_id} references unavailable interface #{module_name}.#{function_name}/#{arity}"
  end

  defp assert_contract_test_location(contract_test, operation_id) do
    {file, label} =
      case contract_test do
        %{"file" => file, "describe" => describe} -> {file, describe}
        contract_test when is_binary(contract_test) -> split_test_location(contract_test)
      end

    absolute_file = Path.expand(file, @root)

    assert String.starts_with?(absolute_file, Path.join(@root, "test/")),
           "#{operation_id} references a test outside the test directory: #{file}"

    assert File.regular?(absolute_file),
           "#{operation_id} references a missing contract-test file: #{file}"

    if label do
      assert File.read!(absolute_file) =~ label,
             "#{operation_id} references a missing contract-test label: #{file}: #{label}"
    end
  end

  defp split_test_location(contract_test) do
    case String.split(contract_test, ": ", parts: 2) do
      [file] -> {file, nil}
      [file, label] -> {file, label}
    end
  end

  defp readme_catalog_row(readme, module) do
    Enum.find(String.split(readme, "\n"), "", &String.starts_with?(&1, "| `#{module}` |"))
  end

  defp interface_documented?(documentation, module, interface) do
    [function, arity] = String.split(interface, "/")
    prefix = if module, do: "#{Regex.escape(module)}\\.", else: ""

    Regex.match?(
      Regex.compile!("`#{prefix}#{Regex.escape(function)}/(?:\\d+,)*#{arity}(?:,\\d+)*`"),
      documentation
    )
  end
end
