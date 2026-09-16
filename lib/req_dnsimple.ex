defmodule ReqDnsimple do
  @moduledoc """
  DNSimple API client for Elixir using Req.

  Configure credentials and account scope once, then pass the client to resource
  operations without repeating the account ID:

      client = ReqDnsimple.new_client(token, account_id: 1010)
      ReqDnsimple.Zone.list_all(client)
      ReqDnsimple.ZoneRecord.list_page(client, "example.com", type: "A")

  Clients are ordinary `Req.Request` structs and remain compatible with
  `Req.merge/2`. Use `new_unscoped_client/2` for identity and account discovery,
  then `for_account/2` to select an account without changing credentials.

  HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
  `{:error, %ReqDnsimple.Error{}}` in both scoped and explicit-account forms.
  Metadata includes pagination, rate-limit information, request IDs, ETags,
  and Retry-After. Complete enumeration retains each page's metadata.
  """

  @type account_id :: integer()
  @type account_id_input :: pos_integer() | binary()
  @type contact_id :: integer()
  @type http_error :: %{
          required(:status) => non_neg_integer(),
          required(:response) => any()
        }
  @type identity :: {:account, term()} | {:user, term()} | {:unknown_token, map()}
  @type record_id :: integer()
  @type sort :: [atom() | {atom(), :asc | :desc}]
  @type token_callback :: (-> binary() | {:bearer, binary()})
  @type zone_id :: integer()
  @type zone_name :: binary()

  @doc """
  Creates an unscoped client using the legacy one-argument interface.

  Prefer `new_client/2` with `:account_id` for ordinary operations, or
  `new_unscoped_client/2` for explicit account discovery. This function retains
  its existing behavior for both user and account tokens.
  """
  @spec new_client(binary() | token_callback()) :: Req.Request.t()
  def new_client(token) when is_binary(token) or is_function(token, 0) do
    ReqDnsimple.Client.new_unscoped(token, [])
  end

  @doc """
  Creates an account-scoped `Req.Request` with credentials and a selected account.

  The required `:account_id` accepts a positive integer or a positive numeric
  string, normalized to an integer. It is required for both user and account
  tokens. Remaining options configure Req, including `:base_url`, `:headers`,
  `:adapter`, and `:retry`. Invalid configuration raises `ArgumentError`.

  Construction makes no HTTP requests and does not evaluate token callbacks.
  A callback is resolved for each request and may return a token string or
  `{:bearer, token}`. Clients remain compatible with `Req.merge/2`.

  Account-scoped operations can omit their account argument. Existing explicit
  account arguments override the selected account for that call only.

  ## Examples

      client = ReqDnsimple.new_client(token, account_id: "1010")
      ReqDnsimple.Zone.list_all(client, name_like: "example")

      client =
        ReqDnsimple.new_client(fn -> System.fetch_env!("DNSIMPLE_TOKEN") end,
          account_id: 1010,
          base_url: "https://api.sandbox.dnsimple.com/v2"
        )

  See `new_unscoped_client/2` for discovery and `for_account/2` for explicit
  account selection without replacing transport configuration or credentials.
  """
  @spec new_client(binary() | token_callback(), keyword()) :: Req.Request.t()
  def new_client(token, opts) do
    ReqDnsimple.Client.new(token, opts)
  end

  @doc """
  Creates an explicitly unscoped client for identity, account discovery, or catalogs.

  Options configure Req; `:account_id` is not accepted. Use `new_client/2` to
  configure an account immediately or `for_account/2` after discovery.

  Both user and account tokens are supported. No HTTP request is made and a
  dynamic token callback is not evaluated during construction.

  Account-free forms of account-scoped operations return
  `{:error, :missing_account_id}` until an account is selected. Global
  operations such as `whoami/1`, `ReqDnsimple.Account.list/1`, and
  `ReqDnsimple.Tld.list_all/1` do not require account scope.

  ## Examples

      discovery = ReqDnsimple.new_unscoped_client(account_token)
      {:account, %{"id" => id}} = ReqDnsimple.whoami(discovery)
      client = ReqDnsimple.for_account(discovery, id)

  For a user token, use `ReqDnsimple.Account.list/1` and explicitly select an
  account. A user identity's ID is not an account ID.
  """
  @spec new_unscoped_client(binary() | token_callback(), keyword()) :: Req.Request.t()
  def new_unscoped_client(token, opts \\ []) do
    ReqDnsimple.Client.new_unscoped(token, opts)
  end

  @doc """
  Returns a copy of a client scoped to the given account.

  Accepts a positive integer or positive numeric string and raises
  `ArgumentError` for invalid IDs. The original request, credentials, and
  transport configuration remain unchanged. No HTTP request is made and token
  callbacks are not evaluated. Selecting an account does not grant access;
  DNSimple still verifies the token's permissions.

  ## Examples

      account_a = ReqDnsimple.for_account(discovery, 1010)
      account_b = ReqDnsimple.for_account(discovery, "2020")
      ReqDnsimple.Zone.list(account_a)
      ReqDnsimple.Zone.list(account_b)
  """
  @spec for_account(Req.Request.t(), account_id_input()) :: Req.Request.t()
  def for_account(req, account_id) do
    ReqDnsimple.Client.for_account(req, account_id)
  end

  @spec token_type(Req.Request.t() | binary()) :: :user_token | :account_token | :unknown_token
  def token_type(%Req.Request{options: %{auth: {:bearer, token}}}) when is_binary(token),
    do: token_type(token)

  def token_type(%Req.Request{options: %{auth: token_fun}}) when is_function(token_fun, 0),
    do: token_type(token_fun.())

  def token_type({:bearer, token}), do: token_type(token)
  def token_type("dnsimple_u_" <> _), do: :user_token
  def token_type("dnsimple_a_" <> _), do: :account_token
  def token_type(x) when is_binary(x), do: :unknown_token

  @doc """
  Returns the authenticated identity reported by DNSimple.

  A response containing exactly one non-null user or account returns the
  corresponding `{:user, user}` or `{:account, account}` tuple as data,
  alongside HTTP metadata. If both identities are present or absent, data is
  `{:unknown_token, body}` with the full response body.
  """
  @spec whoami(Req.Request.t()) ::
          ReqDnsimple.Response.result(identity())
  def whoami(req) do
    req
    |> Req.merge(
      method: :get,
      url: "/whoami"
    )
    |> Req.request()
    |> case do
      {:ok,
       %Req.Response{
         status: 200,
         body: body = %{"data" => %{"user" => user, "account" => account}}
       } = response} ->
        identity =
          case {user, account} do
            {user, nil} when not is_nil(user) -> {:user, user}
            {nil, account} when not is_nil(account) -> {:account, account}
            _ -> {:unknown_token, body}
          end

        ReqDnsimple.Response.ok(identity, response)

      {:ok, response} ->
        response_error(response)

      {:error, e} ->
        ReqDnsimple.Response.error(e)
    end
  end

  @doc """
  Lists all apex NS records using the client's configured account.

  Returns typed `ReqDnsimple.NsRecord` structs and aggregate metadata.
  An unscoped client returns a `ReqDnsimple.Error` with reason
  `:missing_account_id` and no HTTP metadata, without making a request.
  """
  @spec ns_records(Req.Request.t(), binary()) ::
          ReqDnsimple.Response.result([ReqDnsimple.NsRecord.t()])
  def ns_records(req, zone_id) do
    ReqDnsimple.Client.with_account(req, &ns_records(req, &1, zone_id))
  end

  @doc "Lists all apex NS records using an explicit account for this call."
  @spec ns_records(Req.Request.t(), ReqDnsimple.account_id(), binary()) ::
          ReqDnsimple.Response.result([ReqDnsimple.NsRecord.t()])
  def ns_records(req, account_id, zone_id) do
    case ReqDnsimple.ZoneRecord.list_all(req, account_id, zone_id, name: "", type: "NS") do
      {:ok, {records, metadata}} ->
        ReqDnsimple.Response.ok(
          Enum.map(records, &struct(ReqDnsimple.NsRecord, Map.from_struct(&1))),
          metadata
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Lists one page of zones using the client's configured account."
  @spec list_zones(Req.Request.t()) :: ReqDnsimple.Response.result([ReqDnsimple.Zone.t()])
  defdelegate list_zones(req), to: ReqDnsimple.Zone, as: :list

  @doc """
  Lists one page of zones with options, or with an explicit account and default options.

  A keyword list supplies options for the configured account. An integer or
  string selects an explicit account for this call. See `ReqDnsimple.Zone.list/3`.
  """
  @spec list_zones(Req.Request.t(), account_id() | binary() | keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.Zone.t()])
  defdelegate list_zones(req, account_or_opts), to: ReqDnsimple.Zone, as: :list

  @doc "Lists one page of zones using an explicit account and options."
  @spec list_zones(Req.Request.t(), account_id(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.Zone.t()])
  defdelegate list_zones(req, account_id, opts), to: ReqDnsimple.Zone, as: :list

  @doc """
  Lists one page of zones from the configured account and returns `{zones, metadata}`.

  Raises `ReqDnsimple.Error`, retaining its reason and available metadata.
  """
  @spec list_zones!(Req.Request.t()) :: {[ReqDnsimple.Zone.t()], ReqDnsimple.Metadata.t()}
  defdelegate list_zones!(req), to: ReqDnsimple.Zone, as: :list!

  @doc """
  Lists one page of zones and returns `{zones, metadata}`.

  This is the raising counterpart of `list_zones/2`. Raises `ReqDnsimple.Error`
  for error results. The original reason and HTTP metadata are available in
  the exception's `:reason` and `:metadata` fields.

  A keyword-list second argument supplies filtering, sorting, or pagination
  options for the configured account. An integer or string selects an explicit
  account with default options for this call.
  """
  @spec list_zones!(Req.Request.t(), account_id() | binary() | keyword()) ::
          {[ReqDnsimple.Zone.t()], ReqDnsimple.Metadata.t()}
  defdelegate list_zones!(req, account_or_opts), to: ReqDnsimple.Zone, as: :list!

  @doc "Lists zones and metadata using an explicit account and options. Raises on errors."
  @spec list_zones!(Req.Request.t(), account_id(), keyword()) ::
          {[ReqDnsimple.Zone.t()], ReqDnsimple.Metadata.t()}
  defdelegate list_zones!(req, account_id, opts), to: ReqDnsimple.Zone, as: :list!

  @doc "Lists one page of contacts using the client's configured account."
  @spec list_contacts(Req.Request.t()) :: ReqDnsimple.Response.result([ReqDnsimple.Contact.t()])
  defdelegate list_contacts(req), to: ReqDnsimple.Contact, as: :list

  @doc "Lists contacts with scoped options, or an explicit account with default options."
  @spec list_contacts(Req.Request.t(), account_id() | binary() | keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.Contact.t()])
  defdelegate list_contacts(req, account_or_opts), to: ReqDnsimple.Contact, as: :list

  @doc "Lists contacts using an explicit account and options."
  @spec list_contacts(Req.Request.t(), account_id(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.Contact.t()])
  defdelegate list_contacts(req, account_id, opts), to: ReqDnsimple.Contact, as: :list

  @doc "Lists one page of billing charges using the client's configured account."
  @spec list_billing_charges(Req.Request.t()) ::
          ReqDnsimple.Response.result([ReqDnsimple.BillingCharge.t()])
  defdelegate list_billing_charges(req), to: ReqDnsimple.BillingCharge, as: :list

  @doc "Lists charges with scoped options, or an explicit account with default options."
  @spec list_billing_charges(Req.Request.t(), account_id() | binary() | keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.BillingCharge.t()])
  defdelegate list_billing_charges(req, account_or_opts), to: ReqDnsimple.BillingCharge, as: :list

  @doc "Lists billing charges using an explicit account and options."
  @spec list_billing_charges(Req.Request.t(), account_id(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.BillingCharge.t()])
  defdelegate list_billing_charges(req, account_id, opts),
    to: ReqDnsimple.BillingCharge,
    as: :list

  @doc "Lists one page of records with response metadata using the client's configured account."
  @spec list_zone_records(Req.Request.t(), zone_name()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  defdelegate list_zone_records(req, zone_id), to: ReqDnsimple.ZoneRecord, as: :list

  @doc """
  Lists records with scoped options, or an explicit account with default options.

  See `ReqDnsimple.ZoneRecord.list/4` for filters, sorting, and pagination.
  """
  @spec list_zone_records(Req.Request.t(), zone_name(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  @spec list_zone_records(Req.Request.t(), account_id(), zone_name()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  defdelegate list_zone_records(req, account_or_zone, zone_or_opts),
    to: ReqDnsimple.ZoneRecord,
    as: :list

  @doc "Lists one page of records with response metadata using an explicit account and options."
  @spec list_zone_records(Req.Request.t(), account_id(), zone_name(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  defdelegate list_zone_records(req, account_id, zone_id, opts),
    to: ReqDnsimple.ZoneRecord,
    as: :list

  @doc "Gets a zone record using the client's configured account."
  @spec get_zone_record(Req.Request.t(), zone_name(), record_id()) ::
          ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  defdelegate get_zone_record(req, zone_name, record_id),
    to: ReqDnsimple.ZoneRecord,
    as: :get

  @doc "Gets a zone record using an explicit account for this call."
  @spec get_zone_record(Req.Request.t(), account_id(), zone_name(), record_id()) ::
          ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  defdelegate get_zone_record(req, account_id, zone_name, record_id),
    to: ReqDnsimple.ZoneRecord,
    as: :get

  @doc "Deletes a zone record using the client's configured account."
  @spec delete_zone_record(Req.Request.t(), zone_name(), record_id()) ::
          ReqDnsimple.Response.result(nil)
  defdelegate delete_zone_record(req, zone_id, record_id),
    to: ReqDnsimple.ZoneRecord,
    as: :delete

  @doc "Deletes a zone record using an explicit account for this call."
  @spec delete_zone_record(Req.Request.t(), account_id(), zone_name(), record_id()) ::
          ReqDnsimple.Response.result(nil)
  defdelegate delete_zone_record(req, account_id, zone_id, record_id),
    to: ReqDnsimple.ZoneRecord,
    as: :delete

  @create_zone_record_doc """
  Creates a DNS record in the zone named by `zone_id`.

  The three-argument form uses the client's configured account. The
  four-argument form selects an explicit account for this call.

  `attrs` is a keyword list with three required attributes:

    * `:name` - String containing the name relative to the zone; use `""` for
      the zone apex.
    * `:type` - String containing the record type, such as `"A"`, `"TXT"`, or `"MX"`.
    * `:content` - String containing the record value.

  Optional attributes are:

    * `:ttl` - Non-negative integer time-to-live in seconds.
    * `:priority` - Non-negative integer record priority, or `nil` to send JSON `null`.
    * `:regions` - List of region strings, such as `["global"]`.
    * `:integrated_zones` - List of integer integrated-zone IDs and/or `"dnsimple"`.

  Optional attributes are omitted from the request unless supplied. Returns
  `{:ok, {%ReqDnsimple.ZoneRecord{}, %ReqDnsimple.Metadata{}}}` or
  `{:error, %ReqDnsimple.Error{}}`.

  See `ReqDnsimple.ZoneRecord.create/3` for the complete option schema and an example.
  """
  @doc @create_zone_record_doc
  @spec create_zone_record(Req.Request.t(), zone_name(), keyword()) ::
          ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  defdelegate create_zone_record(req, zone_id, attrs),
    to: ReqDnsimple.ZoneRecord,
    as: :create

  @doc @create_zone_record_doc
  @spec create_zone_record(Req.Request.t(), account_id(), zone_name(), keyword()) ::
          ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  defdelegate create_zone_record(req, account_id, zone_id, attrs),
    to: ReqDnsimple.ZoneRecord,
    as: :create

  @doc "Gets the zone file using the client's configured account."
  @spec get_zone_file(Req.Request.t(), zone_name()) :: ReqDnsimple.Response.result(binary())
  defdelegate get_zone_file(req, zone_name), to: ReqDnsimple.Zone, as: :get_zone_file

  @doc "Gets the zone file using an explicit account for this call."
  @spec get_zone_file(Req.Request.t(), account_id(), zone_name()) ::
          ReqDnsimple.Response.result(binary())
  defdelegate get_zone_file(req, account_id, zone_name),
    to: ReqDnsimple.Zone,
    as: :get_zone_file

  @doc "Checks zone distribution using the client's configured account."
  @spec check_zone_distribution(Req.Request.t(), zone_name()) ::
          ReqDnsimple.Response.result(boolean())
  defdelegate check_zone_distribution(req, zone_name),
    to: ReqDnsimple.Zone,
    as: :check_zone_distribution

  @doc "Checks zone distribution using an explicit account for this call."
  @spec check_zone_distribution(Req.Request.t(), account_id(), zone_name()) ::
          ReqDnsimple.Response.result(boolean())
  defdelegate check_zone_distribution(req, account_id, zone_name),
    to: ReqDnsimple.Zone,
    as: :check_zone_distribution

  @doc """
  Unwraps a successful result or raises its error.

  Returns the value inside `{:ok, value}` unchanged. HTTP operations therefore
  unwrap to `{data, metadata}`, including `{nil, metadata}` for bodyless success.
  Pure-helper values, `nil`, and `false` remain unchanged; a standalone `:ok`
  remains `:ok`.

  Raises an existing exception from `{:error, exception}` unchanged. Other
  `{:error, reason}` results raise `ReqDnsimple.Error`, preserving the original
  reason in its `:reason` field.

  Raises `ArgumentError` for unsupported result shapes.
  """
  @spec unwrap!({:ok, value} | :ok | {:error, term()}) :: value | :ok when value: term()
  def unwrap!({:ok, value}), do: value
  def unwrap!(:ok), do: :ok
  def unwrap!({:error, error}) when is_exception(error), do: raise(error)
  def unwrap!({:error, reason}), do: raise(ReqDnsimple.Error, reason: reason)

  def unwrap!(_result),
    do: raise(ArgumentError, "expected {:ok, value}, :ok, or {:error, reason}")

  @doc false
  @spec response_error(Req.Response.t()) :: {:error, ReqDnsimple.Error.t()}
  def response_error(%Req.Response{status: status, body: body} = response) do
    ReqDnsimple.Response.error(%{status: status, response: body}, response)
  end

  @doc false
  @spec validate_keyword_list(term()) ::
          {:ok, keyword()} | {:error, NimbleOptions.ValidationError.t()}
  def validate_keyword_list(value) do
    if Keyword.keyword?(value) do
      {:ok, value}
    else
      {:error,
       %NimbleOptions.ValidationError{
         message: "expected a keyword list",
         value: value
       }}
    end
  end

  @doc false
  @spec validate_options(term(), NimbleOptions.schema()) ::
          {:ok, keyword()} | {:error, NimbleOptions.ValidationError.t()}
  def validate_options(value, schema) do
    with {:ok, options} <- validate_keyword_list(value) do
      NimbleOptions.validate(options, schema)
    end
  end

  @spec from_json(map(), module(), keyword()) :: struct()
  def from_json(json, module, opts) when is_map(json) and is_atom(module) do
    regular_fields = Keyword.get(opts, :regular, [])
    datetime_fields = Keyword.get(opts, :datetime, [])

    json
    |> Map.take(regular_fields ++ datetime_fields)
    |> convert_string_keys_to_atoms()
    |> convert_timestamps(datetime_fields)
    |> then(&struct!(module, &1))
  end

  @doc """
  Converts validated sort options to the DNSimple API's string sort format.

  Bare field atoms default to ascending order.

  ## Examples

      iex> ReqDnsimple.convert_sort_to_string(sort: [name: :desc, id: :asc])
      [sort: "name:desc,id:asc"]

      iex> ReqDnsimple.convert_sort_to_string(sort: [:id, name: :desc])
      [sort: "id:asc,name:desc"]

      iex> ReqDnsimple.convert_sort_to_string(page: 1)
      [page: 1]
  """
  @spec convert_sort_to_string(keyword()) :: keyword()
  def convert_sort_to_string(opts) do
    case Keyword.get(opts, :sort) do
      nil ->
        opts

      sort when is_list(sort) ->
        sort_string =
          sort
          |> Enum.map_join(",", fn
            field when is_atom(field) -> to_string(field) <> ":asc"
            {field, :asc} -> to_string(field) <> ":asc"
            {field, :desc} -> to_string(field) <> ":desc"
          end)

        Keyword.put(opts, :sort, sort_string)
    end
  end

  @doc false
  @spec validate_sort(term(), [atom()]) :: {:ok, sort()} | {:error, binary()}
  def validate_sort(sort, allowed_fields) when is_list(sort) do
    result =
      Enum.reduce_while(sort, :valid, fn entry, :valid ->
        if valid_sort_entry?(entry, allowed_fields) do
          {:cont, :valid}
        else
          {:halt, {:invalid, entry}}
        end
      end)

    case result do
      :valid ->
        {:ok, sort}

      {:invalid, invalid_entry} ->
        {:error,
         "expected fields #{inspect(allowed_fields)} with :asc or :desc directions, got invalid entry: #{inspect(invalid_entry)}"}
    end
  end

  def validate_sort(sort, _allowed_fields),
    do: {:error, "expected a list of sort fields, got: #{inspect(sort)}"}

  defp valid_sort_entry?(field, allowed_fields) when is_atom(field), do: field in allowed_fields

  defp valid_sort_entry?({field, direction}, allowed_fields),
    do: field in allowed_fields and direction in [:asc, :desc]

  defp valid_sort_entry?(_entry, _allowed_fields), do: false

  defp convert_string_keys_to_atoms(map) do
    for {key, value} <- map, into: %{} do
      {String.to_existing_atom(key), value}
    end
  end

  defp convert_timestamps(map, datetime_fields) do
    Enum.reduce(datetime_fields, map, fn field, acc ->
      atom_field = String.to_existing_atom(field)

      case Map.get(acc, atom_field) do
        nil -> acc
        timestamp -> Map.put(acc, atom_field, parse_datetime!(timestamp))
      end
    end)
  end

  defp parse_datetime!(timestamp) do
    {:ok, datetime, _utc_offset} = DateTime.from_iso8601(timestamp)
    datetime
  end
end
