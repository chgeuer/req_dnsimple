defmodule ReqDnsimple.PublicTypespecTest do
  use ExUnit.Case, async: true

  test "public function specs preserve established success and error shapes" do
    assert_spec(ReqDnsimple, :new_client, 1, "binary() | token_callback()")
    assert_spec(ReqDnsimple, :whoami, 1, "{:error, term()}")
    assert_spec(ReqDnsimple, :ns_records, 3, "[ReqDnsimple.NsRecord.t()] | {:error, term()}")

    assert_spec(ReqDnsimple.Account, :list, 1, "[t()] | {:error, any()}")
    assert_spec(ReqDnsimple.Contact, :get, 3, "{:ok, t()} | {:error, term()}")

    for module <- [ReqDnsimple.BillingCharge, ReqDnsimple.Contact, ReqDnsimple.Zone] do
      assert_spec(module, :list, 3, "{:ok, [t()]} | {:error, term()}")
      assert_spec(module, :list_page, 3, "{:ok, {[t()], ReqDnsimple.Pagination.metadata()}}")
      assert_spec(module, :list_all, 3, "{:ok, [t()]} | {:error, term()}")
    end

    assert_spec(
      ReqDnsimple.ZoneRecord,
      :list,
      4,
      "{:ok, {[t()], map()}} | {:error, term()}"
    )

    assert_spec(ReqDnsimple.ZoneRecord, :get, 4, "{:ok, t()} | {:error, term()}")
    assert_spec(ReqDnsimple.ZoneRecord, :delete, 4, ":ok | {:error, term()}")
  end

  test "public resource types represent documented nullable and identifier fields" do
    assert_type(ReqDnsimple.Zone, :t, "last_transferred_at: DateTime.t() | nil")

    assert_type(ReqDnsimple.ZoneRecord, :t, "zone_id: ReqDnsimple.zone_name()")
    assert_type(ReqDnsimple.ZoneRecord, :t, "parent_id: ReqDnsimple.record_id() | nil")
    assert_type(ReqDnsimple.ZoneRecord, :t, "priority: integer() | nil")

    assert_type(ReqDnsimple.NsRecord, :t, "zone_id: ReqDnsimple.zone_name()")
    assert_type(ReqDnsimple.NsRecord, :t, "parent_id: integer() | nil")
    assert_type(ReqDnsimple.NsRecord, :t, "priority: integer() | nil")
  end

  @spec assert_spec(module(), atom(), non_neg_integer(), binary()) :: true
  defp assert_spec(module, name, arity, expected_fragment) do
    {:ok, specs} = Code.Typespec.fetch_specs(module)

    entries =
      Enum.find_value(specs, fn
        {{^name, ^arity}, entries} -> entries
        _entry -> nil
      end)

    assert entries

    assert Enum.any?(entries, fn entry ->
             name
             |> Code.Typespec.spec_to_quoted(entry)
             |> Macro.to_string()
             |> String.contains?(expected_fragment)
           end),
           "#{inspect(module)}.#{name}/#{arity} does not include #{inspect(expected_fragment)}"
  end

  @spec assert_type(module(), atom(), binary()) :: true
  defp assert_type(module, name, expected_fragment) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    type =
      Enum.find_value(types, fn
        {_kind, {^name, _, _} = entry} -> entry
        _entry -> nil
      end)

    assert type

    assert type
           |> Code.Typespec.type_to_quoted()
           |> Macro.to_string()
           |> String.contains?(expected_fragment),
           "#{inspect(module)}.#{name}/0 does not include #{inspect(expected_fragment)}"
  end
end
