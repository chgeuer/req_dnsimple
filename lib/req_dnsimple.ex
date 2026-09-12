defmodule ReqDnsimple do
  @moduledoc """
  DNSimple API client for Elixir using Req.

  Provides client configuration and basic API interaction capabilities.
  """

  @type account_id :: integer()
  @type contact_id :: integer()
  @type http_error :: %{status: non_neg_integer(), response: any()}
  @type record_id :: integer()
  @type sort :: [atom() | {atom(), :asc | :desc}]
  @type token_callback :: (-> binary() | {:bearer, binary()})
  @type zone_id :: integer()
  @type zone_name :: binary()

  @base_url "https://api.dnsimple.com/v2"

  @spec new_client(binary() | token_callback()) :: Req.Request.t()
  def new_client(token) when is_binary(token) do
    Req.new(
      base_url: @base_url,
      auth: {:bearer, token}
    )
  end

  def new_client(token_fun) when is_function(token_fun, 0) do
    Req.new(
      base_url: @base_url,
      auth: fn ->
        case token_fun.() do
          token when is_binary(token) -> {:bearer, token}
          auth -> auth
        end
      end
    )
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
  corresponding `{:user, user}` or `{:account, account}` tuple. If both
  identities are present or absent, the full response body is returned as
  `{:unknown_token, body}`.
  """
  @spec whoami(Req.Request.t()) ::
          {:account, any()} | {:unknown_token, map()} | {:user, any()} | {:error, term()}
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
       }} ->
        case {user, account} do
          {user, nil} when not is_nil(user) -> {:user, user}
          {nil, account} when not is_nil(account) -> {:account, account}
          _ -> {:unknown_token, body}
        end

      {:ok, response} ->
        response_error(response)

      {:error, e} ->
        {:error, e}
    end
  end

  @spec ns_records(Req.Request.t(), ReqDnsimple.account_id(), binary()) ::
          [ReqDnsimple.NsRecord.t()] | {:error, term()}
  def ns_records(req, account_id, zone_id) do
    case ReqDnsimple.ZoneRecord.list_all(req, account_id, zone_id, name: "", type: "NS") do
      {:ok, records} ->
        Enum.map(records, &struct(ReqDnsimple.NsRecord, Map.from_struct(&1)))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defdelegate list_zones(req, account_id), to: ReqDnsimple.Zone, as: :list

  defdelegate list_contacts(req, account_id), to: ReqDnsimple.Contact, as: :list

  defdelegate list_billing_charges(req, account_id), to: ReqDnsimple.BillingCharge, as: :list

  defdelegate list_zone_records(req, account_id, zone_id, opts \\ []),
    to: ReqDnsimple.ZoneRecord,
    as: :list

  defdelegate get_zone_record(req, account_id, zone_name, record_id),
    to: ReqDnsimple.ZoneRecord,
    as: :get

  defdelegate delete_zone_record(req, account_id, zone_id, record_id),
    to: ReqDnsimple.ZoneRecord,
    as: :delete

  defdelegate create_zone_record(req, account_id, zone_id, attrs),
    to: ReqDnsimple.ZoneRecord,
    as: :create

  defdelegate get_zone_file(req, account_id, zone_name),
    to: ReqDnsimple.Zone,
    as: :get_zone_file

  defdelegate check_zone_distribution(req, account_id, zone_name),
    to: ReqDnsimple.Zone,
    as: :check_zone_distribution

  @doc false
  @spec response_error(Req.Response.t()) :: {:error, http_error()}
  def response_error(%Req.Response{status: status, body: body}) do
    {:error, %{status: status, response: body}}
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
    case Enum.find(sort, &(not valid_sort_entry?(&1, allowed_fields))) do
      nil ->
        {:ok, sort}

      invalid_entry ->
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
