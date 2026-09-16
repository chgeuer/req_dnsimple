defmodule ReqDnsimple.DocumentationContractTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @implementation_states ~w(existing implemented pending out-of-scope)
  @out_of_scope_operation_ids ~w(
    getDomainRestore
  )
  @catalog_modules ~w(
    ReqDnsimple.Certificate
    ReqDnsimple.DnsAnalytics
    ReqDnsimple.Dnssec
    ReqDnsimple.OAuth
    ReqDnsimple.RegistrantChange
    ReqDnsimple.Registrar
    ReqDnsimple.Template
    ReqDnsimple.TemplateRecord
    ReqDnsimple.Webhook
  )
  @collection_interfaces %{
    "ReqDnsimple.BillingCharge" =>
      ~w(list/1 list/2 list/3 list_page/1 list_page/2 list_page/3 list_all/1 list_all/2 list_all/3),
    "ReqDnsimple.Contact" =>
      ~w(list/1 list/2 list/3 list_page/1 list_page/2 list_page/3 list_all/1 list_all/2 list_all/3),
    "ReqDnsimple.EmailForward" =>
      ~w(list/2 list/3 list/4 list_page/2 list_page/3 list_page/4 list_all/2 list_all/3 list_all/4),
    "ReqDnsimple.Service" =>
      ~w(list_applied/2 list_applied/3 list_applied/4 list_page_applied/2 list_page_applied/3 list_page_applied/4 list_all_applied/2 list_all_applied/3 list_all_applied/4),
    "ReqDnsimple.Zone" =>
      ~w(list/1 list/2 list/3 list_page/1 list_page/2 list_page/3 list_all/1 list_all/2 list_all/3),
    "ReqDnsimple.ZoneRecord" =>
      ~w(list/2 list/3 list/4 list_page/2 list_page/3 list_page/4 list_all/2 list_all/3 list_all/4)
  }

  test "public guides describe bounded coverage and the versioned inventory states" do
    readme = File.read!(Path.join(@root, "README.md"))
    usage_rules = File.read!(Path.join(@root, "usage-rules.md"))
    inventory = File.read!(Path.join(@root, "docs/audit/operation-inventory.json"))

    refute readme =~ "all DNSimple API operations"
    refute usage_rules =~ "all DNSimple API operations"

    assert readme =~ "docs/audit/operation-inventory.json"
    assert usage_rules =~ "docs/audit/operation-inventory.json"
    assert readme =~ "110 supported operations"
    assert usage_rules =~ "110 supported operations"
    assert readme =~ "One additional"
    assert usage_rules =~ "One additional"
    assert readme =~ "`getDomainRestore`"
    assert usage_rules =~ "`getDomainRestore`"

    for state <- @implementation_states do
      assert readme =~ "`#{state}`"
      assert usage_rules =~ "`#{state}`"
    end

    assert_inventory_states(inventory)
  end

  test "inventory accepts completed supported coverage with no pending operations" do
    inventory = inventory_with_replaced_state("pending", "implemented")

    refute Enum.any?(Jason.decode!(inventory)["operations"], &(&1["implementation"] == "pending"))
    assert_inventory_states(inventory)
  end

  test "inventory reconciles every supported operation with implementation and contract evidence" do
    inventory =
      @root
      |> Path.join("docs/audit/operation-inventory.json")
      |> File.read!()
      |> Jason.decode!()

    assert inventory["approved_operation_count"] == 110
    assert length(inventory["operations"]) == 111

    {scoped, excluded} = Enum.split_with(inventory["operations"], & &1["in_scope"])

    assert length(scoped) == 110
    assert length(excluded) == 1
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

  test "scope inventory preserves every account-free and explicit-account interface family" do
    inventory =
      @root
      |> Path.join("docs/audit/operation-inventory.json")
      |> File.read!()
      |> Jason.decode!()

    assert %{
             "constructor" => "ReqDnsimple.new_client/2",
             "discovery_constructor" => "ReqDnsimple.new_unscoped_client/1,2",
             "account_selection" => "ReqDnsimple.for_account/2",
             "missing_scope_error" =>
               "{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}",
             "account_scoped_operation_count" => 102
           } = inventory["client_scope"]

    {account_operations, other_operations} =
      Enum.split_with(inventory["operations"], fn operation ->
        operation["in_scope"] and String.starts_with?(operation["path"], "/{account}/")
      end)

    assert length(account_operations) == 102
    assert Enum.sum(Enum.map(account_operations, &length(&1["scoped_interfaces"]))) == 144

    for operation <- account_operations do
      assert operation["scoped_interfaces"] != []

      assert %{
               "file" => "test/account_scope_operations_test.exs",
               "describe" => "account-scoped operation parity"
             } in operation["contract_tests"]

      for interface <- operation["scoped_interfaces"] do
        arities = interface["arities"]
        arguments = interface["arguments"]

        assert is_list(arities) and arities != []
        assert Enum.all?(arities, &(is_integer(&1) and &1 > 0))
        assert arities == Enum.sort(Enum.uniq(arities))
        assert Enum.max(arities) == interface["arity"]
        assert is_list(arguments)
        assert length(arguments) == interface["arity"]
        assert ["req" | _] = arguments
        refute "account_id" in arguments

        for arity <- arities do
          assert_exported_interface(
            Map.put(interface, "arity", arity),
            operation["operation_id"]
          )

          assert_exported_interface(
            Map.put(interface, "arity", arity + 1),
            operation["operation_id"]
          )
        end
      end
    end

    for operation <- other_operations do
      assert Map.get(operation, "scoped_interfaces", []) == []
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

  test "public guides prefer scoped clients without abandoning legacy or discovery workflows" do
    for file <- ["README.md", "usage-rules.md"] do
      guide = File.read!(Path.join(@root, file))

      for contract <- [
            "new_client/2",
            "new_client/1",
            "new_unscoped_client/1,2",
            "for_account/2",
            "Req.Request",
            "Req.merge/2",
            "dnsimple_a_",
            "dnsimple_u_",
            "ArgumentError",
            ":missing_account_id",
            "NimbleOptions.ValidationError",
            "scoped_interfaces",
            "client_scope",
            "102 account-path operations",
            "144 interface families",
            "samples/README.md"
          ] do
        assert guide =~ contract, "#{file} omits the #{contract} client contract"
      end

      assert guide =~ "legacy unscoped behavior"
      assert guide =~ "including accepting account tokens"
      refute guide =~ "[account | _]"
    end
  end

  test "Elixir snippets in the public guides are syntactically valid" do
    for file <- ["README.md", "usage-rules.md"],
        [_, snippet] <- Regex.scan(~r/```elixir\n(.*?)```/s, File.read!(Path.join(@root, file))) do
      assert {:ok, _ast} = Code.string_to_quoted(snippet, file: file)
    end
  end

  test "guides describe the uniform HTTP envelope, metadata, and pure helper exception" do
    for file <- ["README.md", "usage-rules.md", "samples/README.md"] do
      guide = File.read!(Path.join(@root, file))

      for contract <- [
            "{:ok, {data, %ReqDnsimple.Metadata{}}}",
            "ReqDnsimple.Error",
            "ReqDnsimple.Response.result(data)",
            "metadata.pagination",
            "metadata.pages",
            "parse_errors",
            "Unix seconds",
            "HTTP-date",
            "ETag",
            "Retry-After",
            "transport",
            "nil",
            "OAuth.authorize_url/2,3",
            "{:ok, url}",
            "{:error, %NimbleOptions.ValidationError{}}"
          ] do
        assert guide =~ contract, "#{file} omits the #{contract} result contract"
      end

      refute guide =~ "Different modules use slightly different return conventions"
      refute guide =~ "returns a bare list"
      refute guide =~ "{records, pagination}"
      refute guide =~ "{:error, :missing_account_id}"
      assert guide =~ ~r/opaque/i

      assert String.replace(guide, "**", "") =~
               ~r/(?:no|does not add) automatic rate\s+limiting, retries, or\s+caching/i
    end
  end

  test "the domain glossary and audit distinguish the current contract from historical scope" do
    glossary = File.read!(Path.join(@root, "CONTEXT.md"))
    assert glossary =~ "ReqDnsimple.Metadata"
    assert glossary =~ "metadata.pages"
    assert glossary =~ "ReqDnsimple.Response.result(data)"
    assert glossary =~ "Unix seconds"
    assert glossary =~ "parse_errors"

    for file <- ["docs/audit/README.md", "docs/audit/api-parity.md"] do
      guide = File.read!(Path.join(@root, file))
      assert guide =~ ~r/historical/i
      assert guide =~ "103"
      assert guide =~ "110"
      assert guide =~ "111 published operations"
      assert guide =~ "`getDomainRestore`"
      assert guide =~ "{:ok, {data, %ReqDnsimple.Metadata{}}}"
      assert guide =~ "schema version 2" or guide =~ "schema\nversion 2"
    end
  end

  test "inventory schema describes metadata-bearing results without altering endpoint scope" do
    inventory =
      @root
      |> Path.join("docs/audit/operation-inventory.json")
      |> File.read!()
      |> Jason.decode!()

    assert inventory["schema_version"] == 2

    assert %{
             "type" => "ReqDnsimple.Response.result(data)",
             "success" => "{:ok, {data, %ReqDnsimple.Metadata{}}}",
             "bodyless_data" => "nil",
             "bang_success" => "{data, metadata}",
             "metadata_type" => "ReqDnsimple.Metadata.t()"
           } = contract = inventory["result_contract"]

    assert Map.keys(contract["metadata_fields"]) |> Enum.sort() ==
             %ReqDnsimple.Metadata{}
             |> Map.from_struct()
             |> Map.keys()
             |> Enum.map(&Atom.to_string/1)
             |> Enum.sort()

    assert contract["aggregate_metadata"]["nil_fields"] ==
             ~w(status pagination request_id etag)

    assert contract["aggregate_metadata"]["last_page_fields"] ==
             ~w(rate_limit rate_limit_remaining rate_limit_reset retry_after parse_errors)

    assert contract["pure_helpers"] =~ "OAuth.authorize_url/2,3"
    assert contract["identity"] =~ "{:unknown_token, body}"
    assert contract["ns_records"] =~ "aggregate_metadata"

    for operation <- inventory["operations"], interface <- operation["proposed_interfaces"] do
      variants = List.wrap(interface["return_values"]["success"])
      aggregate? = interface["role"] == "explicit complete enumeration"
      page? = interface["role"] in ["one explicit API page", "single-page convenience alias"]
      payload = variants |> Enum.map(& &1["payload_type"]) |> Enum.uniq() |> Enum.join(" | ")

      assert interface["response_type"] == "ReqDnsimple.Response.result(#{payload})"

      for success <- variants do
        assert success["metadata_in_success_tuple"] == true
        assert success["pagination_in_metadata"] == page?
        assert success["pagination_in_metadata_pages"] == aggregate?
        assert success["metadata_scope"] == if(aggregate?, do: "aggregate", else: "response")
        refute Map.has_key?(success, "pagination_in_success_tuple")
        assert is_binary(success["payload_type"])

        if success["http_status"] == 204, do: assert(success["payload_type"] == "nil")
      end

      assert %{
               "type" => "ReqDnsimple.Error.t()",
               "reason_type" => "term()",
               "metadata_type" => "ReqDnsimple.Metadata.t() | nil"
             } = interface["return_values"]["error"]
    end
  end

  test "public HTTP example assignments preserve data and metadata" do
    for file <- ["README.md", "usage-rules.md"],
        [_, snippet] <- Regex.scan(~r/```elixir\n(.*?)```/s, File.read!(Path.join(@root, file))) do
      {:ok, ast} = Code.string_to_quoted(snippet, file: file)

      Macro.prewalk(ast, fn
        {:=, _, [pattern, expression]} = node ->
          case example_result_kind(expression) do
            :http ->
              case pattern do
                {:ok, {_data, metadata}} ->
                  assert_metadata_pattern(metadata, file)

                pattern ->
                  assert structured_error_pattern?(pattern),
                         "#{file} HTTP example must consume {:ok, {data, metadata}} or a structured error"
              end

            :unwrapped ->
              assert {_data, metadata} = pattern,
                     "#{file} bang example must preserve {data, metadata}"

              assert_metadata_pattern(metadata, file)

            :pure ->
              :ok
          end

          node

        node ->
          node
      end)
    end
  end

  test "standalone record documentation retains nullable priorities" do
    for file <- ["README.md", "usage-rules.md"] do
      guide = File.read!(Path.join(@root, file))
      assert guide =~ ~r/`priority` also accepts `nil`/
      assert guide =~ "JSON `null`"
      assert guide =~ "Batch record priorities remain non-negative integers only"
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

  test "scoped and legacy functions used by the public examples are exported" do
    exports = [
      {ReqDnsimple, :new_client, [1, 2]},
      {ReqDnsimple, :new_unscoped_client, [1, 2]},
      {ReqDnsimple, :for_account, [2]},
      {ReqDnsimple, :whoami, [1]},
      {ReqDnsimple, :ns_records, [2, 3]},
      {ReqDnsimple, :list_zones, [1, 2, 3]},
      {ReqDnsimple, :list_zones!, [1, 2, 3]},
      {ReqDnsimple, :list_contacts, [1, 2, 3]},
      {ReqDnsimple, :list_billing_charges, [1, 2, 3]},
      {ReqDnsimple, :create_zone_record, [3, 4]},
      {ReqDnsimple, :unwrap!, [1]},
      {ReqDnsimple.OAuth, :authorize_url, [2, 3]},
      {ReqDnsimple.OAuth, :exchange_code, [2]},
      {ReqDnsimple.Account, :list, [1]},
      {ReqDnsimple.Zone, :list, [1, 2, 3]},
      {ReqDnsimple.Zone, :list!, [1, 2, 3]},
      {ReqDnsimple.Zone, :get, [2, 3]},
      {ReqDnsimple.Zone, :list_page, [1, 2, 3]},
      {ReqDnsimple.Zone, :list_all, [1, 2, 3]},
      {ReqDnsimple.ZoneRecord, :list, [2, 3, 4]},
      {ReqDnsimple.ZoneRecord, :list_page, [2, 3, 4]},
      {ReqDnsimple.ZoneRecord, :list_all, [2, 3, 4]},
      {ReqDnsimple.ZoneRecord, :create, [3, 4]},
      {ReqDnsimple.ZoneRecord, :update, [4, 5]},
      {ReqDnsimple.ZoneRecord, :delete, [3, 4]},
      {ReqDnsimple.ZoneRecord, :batch_change, [3, 4]},
      {ReqDnsimple.BillingCharge, :list, [1, 2, 3]},
      {ReqDnsimple.Contact, :list, [1, 2, 3]},
      {ReqDnsimple.Contact, :get, [2, 3]},
      {ReqDnsimple.Contact, :delete, [2, 3]},
      {ReqDnsimple.Registrar, :disable_auto_renewal, [2, 3]},
      {ReqDnsimple.Registrar, :get_registration, [3, 4]},
      {ReqDnsimple.Registrar, :get_renewal, [3, 4]},
      {ReqDnsimple.Registrar, :get_transfer, [3, 4]},
      {ReqDnsimple.Registrar, :cancel_transfer, [3, 4]},
      {ReqDnsimple.Registrar, :change_delegation_to_vanity, [3, 4]},
      {ReqDnsimple.Registrar, :change_delegation_from_vanity, [2, 3]},
      {ReqDnsimple.RegistrantChange, :check, [2, 3]},
      {ReqDnsimple.PrimaryServer, :get, [2, 3]},
      {ReqDnsimple.PrimaryServer, :list, [1, 2, 3]},
      {ReqDnsimple.PrimaryServer, :list_page, [1, 2, 3]},
      {ReqDnsimple.PrimaryServer, :list_all, [1, 2, 3]},
      {ReqDnsimple.PrimaryServer, :unlink, [3, 4]},
      {ReqDnsimple.PrimaryServer, :delete, [2, 3]},
      {ReqDnsimple.SecondaryZone, :create, [2, 3]},
      {ReqDnsimple.Service, :list_page, [1, 2]},
      {ReqDnsimple.Service, :list_all, [1, 2]},
      {ReqDnsimple.Service, :list_page_applied, [2, 3, 4]},
      {ReqDnsimple.Service, :list_all_applied, [2, 3, 4]},
      {ReqDnsimple.Service, :apply, [3, 4, 5]},
      {ReqDnsimple.Service, :unapply, [3, 4]}
    ]

    for {module, function, arities} <- exports, arity <- arities do
      assert Code.ensure_loaded?(module), "expected #{inspect(module)} to load"

      assert function_exported?(module, function, arity),
             "expected #{inspect(module)}.#{function}/#{arity} to be exported"
    end
  end

  test "the top-level record creation helper documents its accepted attributes" do
    assert_creation_documentation(ReqDnsimple, :create_zone_record)
  end

  test "record creation documents its accepted attributes" do
    assert_creation_documentation(ReqDnsimple.ZoneRecord, :create)
  end

  defp assert_creation_documentation(module, function) do
    assert {:docs_v1, _, :elixir, _, _, _, entries} = Code.fetch_docs(module)
    assert {:ok, specs} = Code.Typespec.fetch_specs(module)

    for arity <- [3, 4] do
      entry =
        Enum.find(entries, fn {identifier, _, _, _, _} ->
          identifier == {:function, function, arity}
        end)

      assert {{:function, ^function, ^arity}, _, _, %{"en" => documentation}, _} = entry
      assert documentation =~ "keyword list"
      assert documentation =~ "required"

      for attribute <- ~w(name type content ttl priority regions integrated_zones) do
        assert documentation =~ "`:#{attribute}`"
      end

      assert Enum.any?(specs, fn {identifier, _} -> identifier == {function, arity} end)
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

  defp example_result_kind({:|>, _, [expression, function]}) do
    if example_result_kind(function) == :unwrapped and example_result_kind(expression) == :http,
      do: :unwrapped,
      else: example_result_kind(function)
  end

  defp example_result_kind({{:., _, [{:__aliases__, _, [:ReqDnsimple | _]}, function]}, _, _}) do
    cond do
      function in [
        :new_client,
        :new_unscoped_client,
        :for_account,
        :authorize_url,
        :token_type,
        :from_json,
        :convert_sort_to_string
      ] ->
        :pure

      function in [:unwrap!, :list!, :list_zones!] ->
        :unwrapped

      true ->
        :http
    end
  end

  defp example_result_kind(_expression), do: :pure

  defp structured_error_pattern?(
         {:error, {:%, _, [{:__aliases__, _, [:ReqDnsimple, :Error]}, _fields]}}
       ),
       do: true

  defp structured_error_pattern?(_pattern), do: false

  defp assert_metadata_pattern({name, _, context}, file)
       when is_atom(name) and is_atom(context) do
    assert String.ends_with?(Atom.to_string(name), "metadata"),
           "#{file} must bind response metadata, not a former pagination map"
  end

  defp assert_metadata_pattern(_pattern, file) do
    flunk("#{file} must bind the response metadata alongside its data")
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
