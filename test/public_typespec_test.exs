defmodule ReqDnsimple.PublicTypespecTest do
  use ExUnit.Case, async: true

  test "public function specs expose uniform HTTP data and metadata results" do
    assert_spec(ReqDnsimple, :new_client, 1, "binary() | token_callback()")
    assert_spec(ReqDnsimple, :whoami, 1, "ReqDnsimple.Response.result(identity())")

    assert_spec(
      ReqDnsimple,
      :ns_records,
      3,
      "ReqDnsimple.Response.result([ReqDnsimple.NsRecord.t()])"
    )

    assert_spec(ReqDnsimple.Account, :list, 1, "ReqDnsimple.Response.result([t()])")
    assert_spec(ReqDnsimple.Contact, :get, 3, "ReqDnsimple.Response.result(t())")
    assert_spec(ReqDnsimple.Contact, :delete, 3, "ReqDnsimple.Response.result(nil)")

    assert_spec(
      ReqDnsimple.PrimaryServer,
      :list,
      3,
      "ReqDnsimple.Response.result([t()])"
    )

    assert_spec(
      ReqDnsimple.PrimaryServer,
      :list_page,
      3,
      "ReqDnsimple.Response.result([t()])"
    )

    assert_spec(
      ReqDnsimple.PrimaryServer,
      :list_all,
      3,
      "ReqDnsimple.Response.result([t()])"
    )

    assert_spec(
      ReqDnsimple.PrimaryServer,
      :unlink,
      4,
      "ReqDnsimple.Response.result(t())"
    )

    assert_spec(ReqDnsimple.PrimaryServer, :delete, 3, "ReqDnsimple.Response.result(nil)")

    assert_spec(
      ReqDnsimple.SecondaryZone,
      :create,
      3,
      "ReqDnsimple.Response.result(ReqDnsimple.Zone.t())"
    )

    assert_spec(
      ReqDnsimple.Registrar,
      :disable_auto_renewal,
      3,
      "ReqDnsimple.Response.result(nil)"
    )

    for module <- [ReqDnsimple.BillingCharge, ReqDnsimple.Contact, ReqDnsimple.Zone] do
      assert_spec(module, :list, 3, "ReqDnsimple.Response.result([t()])")
      assert_spec(module, :list_page, 3, "ReqDnsimple.Response.result([t()])")
      assert_spec(module, :list_all, 3, "ReqDnsimple.Response.result([t()])")
    end

    assert_spec(
      ReqDnsimple.ZoneRecord,
      :list,
      4,
      "ReqDnsimple.Response.result([t()])"
    )

    assert_spec(ReqDnsimple.ZoneRecord, :get, 4, "ReqDnsimple.Response.result(t())")
    assert_spec(ReqDnsimple.ZoneRecord, :delete, 4, "ReqDnsimple.Response.result(nil)")
  end

  test "bang helper specs retain metadata after unwrapping successful HTTP results" do
    assert_spec(ReqDnsimple.Zone, :list!, 3, "{[t()], ReqDnsimple.Metadata.t()}")

    assert_spec(
      ReqDnsimple,
      :list_zones!,
      2,
      "{[ReqDnsimple.Zone.t()], ReqDnsimple.Metadata.t()}"
    )
  end

  test "response types preserve typed data, metadata, identity tags, and structured errors" do
    assert_type(
      ReqDnsimple.Response,
      :result,
      "result(data) :: {:ok, {data, ReqDnsimple.Metadata.t()}} | {:error, ReqDnsimple.Error.t()}",
      1
    )

    assert_type(ReqDnsimple.Error, :t, "reason: term()")
    assert_type(ReqDnsimple.Error, :t, "metadata: ReqDnsimple.Metadata.t() | nil")

    for field <- [:status, :rate_limit, :rate_limit_remaining, :rate_limit_reset] do
      assert_type(ReqDnsimple.Metadata, :t, "#{field}: non_neg_integer() | nil")
    end

    for field <- [:request_id, :etag, :retry_after] do
      assert_type(ReqDnsimple.Metadata, :t, "#{field}: binary() | nil")
    end

    assert_type(ReqDnsimple.Metadata, :t, "pagination: pagination() | nil")
    assert_type(ReqDnsimple.Metadata, :t, "pages: [t()]")
    assert_type(ReqDnsimple.Metadata, :t, "parse_errors: %{required(atom()) => parse_error()}")

    assert_type(
      ReqDnsimple.Metadata,
      :parse_error,
      "{:invalid_header, term()} | {:invalid_pagination, term()}"
    )

    assert_type(
      ReqDnsimple,
      :identity,
      "{:account, term()} | {:user, term()} | {:unknown_token, map()}"
    )
  end

  test "public resource types represent documented nullable and identifier fields" do
    assert_type(ReqDnsimple.Zone, :t, "last_transferred_at: DateTime.t() | nil")
    assert_type(ReqDnsimple.Zone, :t, "active: boolean() | nil")

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

    signatures =
      Enum.map(entries, fn entry ->
        name
        |> Code.Typespec.spec_to_quoted(entry)
        |> Macro.to_string()
      end)

    assert Enum.any?(signatures, &String.contains?(&1, expected_fragment)),
           "#{inspect(module)}.#{name}/#{arity} does not include #{inspect(expected_fragment)}:\n" <>
             Enum.join(signatures, "\n")
  end

  @spec assert_type(module(), atom(), binary(), non_neg_integer()) :: true
  defp assert_type(module, name, expected_fragment, arity \\ 0) do
    {:ok, types} = Code.Typespec.fetch_types(module)

    type =
      Enum.find_value(types, fn
        {_kind, {^name, _, arguments} = entry} when length(arguments) == arity -> entry
        _entry -> nil
      end)

    assert type

    declaration = type |> Code.Typespec.type_to_quoted() |> Macro.to_string()

    assert String.contains?(declaration, expected_fragment),
           "#{inspect(module)}.#{name}/#{arity} does not include #{inspect(expected_fragment)}:\n" <>
             declaration
  end
end
