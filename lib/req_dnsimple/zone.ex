defmodule ReqDnsimple.Zone do
  @moduledoc """
  DNSimple Zone API functionality.
  Provides zone management operations.
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
          last_transferred_at: DateTime.t()
        }

  defstruct ~w(id account_id name active reverse secondary created_at updated_at last_transferred_at)a

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
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @list_zones_schema),
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
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @list_zones_schema) do
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
