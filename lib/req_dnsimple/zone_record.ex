defmodule ReqDnsimple.ZoneRecord do
  @moduledoc """
  DNSimple Zone Record API functionality.
  Provides zone record CRUD operations.
  """

  # https://developer.dnsimple.com/v2/zones/records/

  @type t :: %__MODULE__{
          id: ReqDnsimple.record_id(),
          zone_id: ReqDnsimple.zone_name(),
          name: binary(),
          content: binary(),
          ttl: integer(),
          priority: integer() | nil,
          type: binary(),
          regions: [binary()],
          parent_id: ReqDnsimple.record_id() | nil,
          system_record: boolean(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id zone_id name content ttl priority type regions parent_id system_record created_at updated_at)a

  @spec from_json(map()) :: t()
  def from_json(json) do
    ReqDnsimple.from_json(json, __MODULE__,
      regular: ~w[id zone_id name content ttl priority type regions parent_id system_record],
      datetime: ~w[created_at updated_at]
    )
  end

  @list_zone_records_schema [
    name_like: [type: :string, doc: "Records containing a specific string"],
    name: [type: :string, doc: "Records with exact name match"],
    type: [type: :string, doc: "Records with specific record type (A, AAAA, CNAME, etc.)"],
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :name, :content, :type]]},
      doc: "Sort by field (id, name, content, type). Format: [name: :desc] or [:id, name: :desc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: :pos_integer, doc: "Number of records per page"]
  ]

  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          {:ok, {[ReqDnsimple.ZoneRecord.t()], map()}}
          | {:error, term()}
  def list(req, account_id, zone_id, opts \\ []) do
    list_page(req, account_id, zone_id, opts)
  end

  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          {:ok, {[ReqDnsimple.ZoneRecord.t()], ReqDnsimple.Pagination.metadata()}}
          | {:error, term()}
  def list_page(req, account_id, zone_id, opts \\ []) do
    # https://developer.dnsimple.com/v2/zones/records/#listZoneRecords

    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @list_zone_records_schema) do
      params =
        validated_opts
        |> ReqDnsimple.convert_sort_to_string()
        |> Map.new()

      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/zones/:zone_id/records",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            zone_id: zone_id
          ],
          params: params
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data, "pagination" => pagination}}} ->
          {:ok, {data |> Enum.map(&ReqDnsimple.ZoneRecord.from_json/1), pagination}}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, e} ->
          {:error, e}
      end
    end
  end

  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          {:ok, [ReqDnsimple.ZoneRecord.t()]} | {:error, term()}
  def list_all(req, account_id, zone_id, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, zone_id, &1))
  end

  @spec get(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name(),
          ReqDnsimple.record_id()
        ) ::
          {:ok, ReqDnsimple.ZoneRecord.t()} | {:error, term()}
  def get(req, account_id, zone_name, record_id) do
    # https://developer.dnsimple.com/v2/zones/records/#getZoneRecord

    req =
      Req.merge(req,
        method: :get,
        url: "/:account_id/zones/:zone_name/records/:record_id",
        path_params_style: :colon,
        path_params: [
          account_id: account_id,
          zone_name: zone_name,
          record_id: record_id
        ]
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, ReqDnsimple.ZoneRecord.from_json(data)}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        {:error, e}
    end
  end

  @integrated_zones_schema [
    type: {:list, {:or, [:integer, {:in, ["dnsimple"]}]}},
    doc: ~s(Zone IDs and the "dnsimple" target)
  ]

  @zone_record_schema [
    name: [type: :string, required: true, doc: "Record name without domain"],
    type: [type: :string, required: true, doc: "Record type (A, AAAA, CNAME, MX, etc.)"],
    content: [type: :string, required: true, doc: "Record content"],
    ttl: [type: :non_neg_integer, doc: "Time-to-live in seconds"],
    priority: [type: :non_neg_integer, doc: "Priority (for MX records)"],
    regions: [type: {:list, :string}, doc: "Geographical regions"],
    integrated_zones: @integrated_zones_schema
  ]

  @spec create(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          {:ok, ReqDnsimple.ZoneRecord.t()} | {:error, term()}
  def create(req, account_id, zone_id, attrs) when is_list(attrs) do
    # https://developer.dnsimple.com/v2/zones/records/#createZoneRecord

    with {:ok, validated_attrs} <- NimbleOptions.validate(attrs, @zone_record_schema) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/zones/:zone_id/records",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            zone_id: zone_id
          ],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: body}} ->
          case {status, body} do
            {201, %{"data" => data}} ->
              {:ok, ReqDnsimple.ZoneRecord.from_json(data)}

            {200, %{"data" => data}} ->
              {:ok, ReqDnsimple.ZoneRecord.from_json(data)}

            {404, _} ->
              {:error, :not_found}

            {400, %{"errors" => errors, "message" => message}} ->
              {:error, %{status: 400, message: message, errors: errors}}

            {_status, _} ->
              ReqDnsimple.response_error(%Req.Response{status: status, body: body})
          end

        {:error, e} ->
          {:error, e}
      end
    end
  end

  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary(), integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, zone_id, record_id) do
    # https://developer.dnsimple.com/v2/zones/records/#deleteZoneRecord

    req =
      Req.merge(req,
        method: :delete,
        url: "/:account_id/zones/:zone_id/records/:record_id",
        path_params_style: :colon,
        path_params: [
          account_id: account_id,
          zone_id: zone_id,
          record_id: record_id
        ]
      )

    case Req.request(req) do
      {:ok, %Req.Response{status: 204}} ->
        :ok

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        {:error, e}
    end
  end

  @update_zone_record_schema [
    name: [type: :string, doc: "Record name without domain"],
    content: [type: :string, doc: "Record content"],
    ttl: [type: :non_neg_integer, doc: "Time-to-live in seconds"],
    priority: [type: :non_neg_integer, doc: "Priority (for MX records)"],
    regions: [type: {:list, :string}, doc: "Geographical regions"],
    integrated_zones: @integrated_zones_schema
  ]

  @spec update(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary(),
          ReqDnsimple.record_id(),
          keyword()
        ) ::
          {:ok, ReqDnsimple.ZoneRecord.t()} | {:error, term()}
  def update(req, account_id, zone_id, record_id, attrs) when is_list(attrs) do
    # https://developer.dnsimple.com/v2/zones/records/#updateZoneRecord

    with {:ok, validated_attrs} <- NimbleOptions.validate(attrs, @update_zone_record_schema) do
      req =
        Req.merge(req,
          method: :patch,
          url: "/:account_id/zones/:zone_id/records/:record_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            zone_id: zone_id,
            record_id: record_id
          ],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: body}} ->
          case {status, body} do
            {200, %{"data" => data}} ->
              {:ok, ReqDnsimple.ZoneRecord.from_json(data)}

            {404, _} ->
              {:error, :not_found}

            {400, %{"errors" => errors, "message" => message}} ->
              {:error, %{status: 400, message: message, errors: errors}}

            {_status, _} ->
              ReqDnsimple.response_error(%Req.Response{status: status, body: body})
          end

        {:error, e} ->
          {:error, e}
      end
    end
  end
end
