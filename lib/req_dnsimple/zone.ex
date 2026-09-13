defmodule ReqDnsimple.Zone do
  @moduledoc """
  DNSimple Zone API functionality.
  Provides zone management operations.

  ## Activating DNS service

      ReqDnsimple.Zone.activate(req, 1010, "example.test")
      #=> {:ok, %ReqDnsimple.Zone{active: true}}

  Activation sends one bodyless request and returns the resulting zone. DNSimple
  may renew an expired domain subscription and charge the account as part of
  activation; this client performs no billing preflight or additional mutation.

  ## Updating apex NS records

      ReqDnsimple.Zone.update_ns_records(req, 1010, "example.test",
        ns_names: ["ns1.example.test", "ns2.example.test"],
        ns_set_ids: [7]
      )
      #=> {:ok, [%ReqDnsimple.ZoneRecord{}]}

  At least one of `:ns_names` or `:ns_set_ids` is required; both may be sent,
  and explicit empty lists are preserved. Callers retaining vanity name-server
  configuration must include its names or sets themselves. This operation
  replaces hosted-zone apex NS records only and does not change registrar
  delegation.
  """

  # https://developer.dnsimple.com/v2/zones/

  @type t :: %__MODULE__{
          id: ReqDnsimple.zone_id(),
          account_id: ReqDnsimple.account_id(),
          name: ReqDnsimple.zone_name(),
          active: boolean(),
          reverse: boolean(),
          secondary: boolean(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          last_transferred_at: DateTime.t() | nil
        }

  defstruct ~w(id account_id name active reverse secondary created_at updated_at last_transferred_at)a

  @activation_path_schema [
    account_id: [type: :integer, required: true],
    zone: [type: :string, required: true]
  ]

  @doc """
  Activates DNS service for a zone and returns the resulting zone.

  DNSimple may renew an expired domain subscription and charge the account.
  This function sends only the requested activation and performs no billing
  preflight, registration, or follow-up request.
  """
  @spec activate(Req.Request.t(), ReqDnsimple.account_id(), ReqDnsimple.zone_name()) ::
          {:ok, t()} | {:error, term()}
  def activate(req, account_id, zone) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, zone: zone],
             @activation_path_schema
           ) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/zones/:zone/activation",
          path_params_style: :colon,
          path_params: [account_id: account_id, zone: zone]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, zone} -> {:ok, zone}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @spec from_json(map()) :: t()
  defp from_json(json) do
    ReqDnsimple.from_json(json, __MODULE__,
      regular: ~w[id account_id name active reverse secondary],
      datetime: ~w[created_at updated_at last_transferred_at]
    )
  end

  @list_zones_schema [
    name_like: [type: :string, doc: "Filter zones containing a specific string"],
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :name]]},
      doc: "Sort by field (id, name). Format: [name: :desc] or [:id, name: :desc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: :pos_integer, doc: "Number of records per page"]
  ]

  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [__MODULE__.t()]} | {:error, term()}
  def list(req, account_id, opts \\ []) do
    with {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_zones_schema),
         {:ok, %Req.Response{status: 200, body: %{"data" => data}}} <-
           request_list(req, account_id, validated_opts) do
      {:ok, Enum.map(data, &from_json/1)}
    else
      {:ok, %Req.Response{status: 404}} -> {:error, :not_found}
      {:ok, response} -> ReqDnsimple.response_error(response)
      {:error, error} -> {:error, error}
    end
  end

  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {[__MODULE__.t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, opts \\ []) do
    with {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_zones_schema) do
      case request_list(req, account_id, validated_opts) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data, "pagination" => pagination}}} ->
          {:ok, {Enum.map(data, &from_json/1), pagination}}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, e} ->
          {:error, e}
      end
    end
  end

  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [__MODULE__.t()]} | {:error, term()}
  def list_all(req, account_id, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  defp request_list(req, account_id, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> Req.merge(
      method: :get,
      url: "/:account_id/zones",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end

  defp decode(%{
         "id" => id,
         "account_id" => account_id,
         "name" => name,
         "reverse" => reverse,
         "secondary" => secondary,
         "last_transferred_at" => last_transferred_at,
         "active" => active,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(account_id) and is_binary(name) and is_boolean(reverse) and
              is_boolean(secondary) and is_boolean(active) do
    with {:ok, last_transferred_at} <- parse_nullable_datetime(last_transferred_at),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         name: name,
         reverse: reverse,
         secondary: secondary,
         last_transferred_at: last_transferred_at,
         active: active,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_nullable_datetime(nil), do: {:ok, nil}
  defp parse_nullable_datetime(value), do: parse_datetime(value)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  @update_ns_records_path_schema [
    account_id: [type: :integer, required: true],
    zone: [type: {:or, [:string, :integer]}, required: true]
  ]

  @update_ns_records_schema [
    ns_names: [type: {:list, :string}],
    ns_set_ids: [type: {:list, :integer}]
  ]

  @doc """
  Replaces a hosted zone's apex NS records.

  Accepts explicit name-server names, name-server-set IDs, or both. This sends
  exactly one update request and performs no lookup, merge, or delegation
  change.
  """
  @spec update_ns_records(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name() | ReqDnsimple.zone_id(),
          keyword()
        ) ::
          {:ok, [ReqDnsimple.ZoneRecord.t()]} | {:error, term()}
  def update_ns_records(req, account_id, zone, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, zone: zone],
             @update_ns_records_path_schema
           ),
         {:ok, validated_attrs} <- validate_ns_record_attrs(attrs) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/zones/:zone/ns_records",
          path_params_style: :colon,
          path_params: [account_id: account_id, zone: zone],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case ReqDnsimple.ZoneRecord.decode_list(data) do
            {:ok, records} -> {:ok, records}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_ns_record_attrs(attrs) do
    with {:ok, attrs} <- ReqDnsimple.validate_keyword_list(attrs),
         {:ok, validated_attrs} <- NimbleOptions.validate(attrs, @update_ns_records_schema) do
      if Keyword.has_key?(validated_attrs, :ns_names) or
           Keyword.has_key?(validated_attrs, :ns_set_ids) do
        {:ok, validated_attrs}
      else
        {:error,
         %NimbleOptions.ValidationError{
           message: "expected at least one of :ns_names or :ns_set_ids",
           key: :ns_names,
           value: nil
         }}
      end
    end
  end

  @spec get_zone_file(Req.Request.t(), ReqDnsimple.account_id(), ReqDnsimple.zone_name()) ::
          {:ok, binary()} | {:error, term()}
  def get_zone_file(req, account_id, zone_name) do
    # https://developer.dnsimple.com/v2/zones/#getZoneFile

    req =
      Req.merge(req,
        method: :get,
        url: "/:account/zones/:zone/file",
        path_params_style: :colon,
        path_params: [
          account: account_id,
          zone: zone_name
        ]
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"zone" => zone_file}}}} ->
        {:ok, zone_file}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        {:error, e}
    end
  end

  @spec check_zone_distribution(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name()
        ) ::
          {:ok, boolean()} | {:error, term()}
  def check_zone_distribution(req, account_id, zone_name) do
    # https://developer.dnsimple.com/v2/zones/#checkZoneDistribution

    req =
      Req.merge(req,
        method: :get,
        url: "/:account/zones/:zone/distribution",
        path_params_style: :colon,
        path_params: [
          account: account_id,
          zone: zone_name
        ]
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"distributed" => distributed}}}} ->
        {:ok, distributed}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: 504}} ->
        {:error, :timeout}

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        {:error, e}
    end
  end
end
