defmodule ReqDnsimple.ZoneRecord do
  @moduledoc """
  DNSimple Zone Record API functionality.
  Provides zone record CRUD and atomic batch operations.

  Batch changes are sent as one request. DNSimple processes deletes first,
  followed by updates and creates; operation order within each list is
  preserved.

  ## Example

      ReqDnsimple.ZoneRecord.batch_change(req, 1010, "example.test",
        creates: [[name: "", type: "MX", content: "mail.example.test", ttl: 0]],
        updates: [[id: 302, content: "192.0.2.2"]],
        deletes: [[id: 303]]
      )
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

  defmodule DeletedRecord do
    @moduledoc "A record deleted by an atomic batch change."

    @type t :: %__MODULE__{id: ReqDnsimple.record_id()}

    defstruct [:id]
  end

  defmodule BatchResult do
    @moduledoc "The records created, updated, and deleted by an atomic batch change."

    @type t :: %__MODULE__{
            creates: [ReqDnsimple.ZoneRecord.t()],
            updates: [ReqDnsimple.ZoneRecord.t()],
            deletes: [ReqDnsimple.ZoneRecord.DeletedRecord.t()]
          }

    defstruct creates: [], updates: [], deletes: []
  end

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

  @check_distribution_schema [
    account_id: [type: :integer, required: true],
    zone_name: [type: :string, required: true],
    record_id: [type: :integer, required: true]
  ]

  @doc """
  Checks whether an individual zone record is distributed to all name servers.

  ## Example

      ReqDnsimple.ZoneRecord.check_distribution(req, 1010, "example.test", 1)
      #=> {:ok, true}
  """
  @spec check_distribution(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name(),
          ReqDnsimple.record_id()
        ) ::
          {:ok, boolean()} | {:error, term()}
  def check_distribution(req, account_id, zone_name, record_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, zone_name: zone_name, record_id: record_id],
             @check_distribution_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/zones/:zone_name/records/:record_id/distribution",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            zone_name: zone_name,
            record_id: record_id
          ]
        )

      case Req.request(req) do
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => %{"distributed" => distributed}}
         }}
        when is_boolean(distributed) ->
          {:ok, distributed}

        {:ok, %Req.Response{status: 401}} ->
          {:error, :unauthorized}

        {:ok, %Req.Response{status: 404}} ->
          {:error, :not_found}

        {:ok, %Req.Response{status: 504}} ->
          {:error, :timeout}

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
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

  @record_types ~w[A AAAA ALIAS CAA CNAME DNSKEY DS HINFO MX NAPTR NS POOL PTR SOA SPF SRV SSHFP TXT URL]
  @record_regions ~w[global SV1 ORD IAD AMS TKO SYD CDG FRA]

  @batch_create_schema [
    name: [type: :string, required: true],
    type: [type: {:in, @record_types}, required: true],
    content: [type: :string, required: true],
    ttl: [type: :non_neg_integer],
    priority: [type: :non_neg_integer],
    regions: [type: {:list, {:in, @record_regions}}]
  ]

  @batch_update_schema [
    id: [type: :integer, required: true],
    name: [type: :string],
    content: [type: :string],
    ttl: [type: :non_neg_integer],
    priority: [type: :non_neg_integer],
    regions: [type: {:list, {:in, @record_regions}}]
  ]

  @batch_delete_schema [
    id: [type: :integer, required: true]
  ]

  @batch_change_schema [
    creates: [
      type:
        {:list,
         {:or,
          [
            {:keyword_list, @batch_create_schema},
            {:map, @batch_create_schema}
          ]}}
    ],
    updates: [
      type:
        {:list,
         {:or,
          [
            {:keyword_list, @batch_update_schema},
            {:map, @batch_update_schema}
          ]}}
    ],
    deletes: [
      type:
        {:list,
         {:or,
          [
            {:keyword_list, @batch_delete_schema},
            {:map, @batch_delete_schema}
          ]}}
    ]
  ]

  @spec batch_change(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name(),
          keyword()
        ) ::
          {:ok, BatchResult.t()} | {:error, term()}
  def batch_change(req, account_id, zone_name, attrs) when is_list(attrs) do
    with {:ok, validated_attrs} <- NimbleOptions.validate(attrs, @batch_change_schema) do
      body =
        Map.new(validated_attrs, fn {operation, records} ->
          {operation, Enum.map(records, &Map.new/1)}
        end)

      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/zones/:zone_name/batch",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            zone_name: zone_name
          ],
          json: body,
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_batch_result(data) do
            {:ok, result} -> {:ok, result}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok,
         %Req.Response{
           status: 400,
           body: %{"message" => message, "errors" => errors}
         }}
        when is_binary(message) and is_map(errors) ->
          {:error, %{status: 400, message: message, errors: errors}}

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

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

  defp decode_batch_result(%{
         "creates" => creates,
         "updates" => updates,
         "deletes" => deletes
       })
       when is_list(creates) and is_list(updates) and is_list(deletes) do
    with {:ok, created_records} <- decode_list(creates),
         {:ok, updated_records} <- decode_list(updates),
         {:ok, deleted_records} <- decode_deleted_records(deletes) do
      {:ok,
       %BatchResult{
         creates: created_records,
         updates: updated_records,
         deletes: deleted_records
       }}
    else
      :error -> :error
    end
  end

  defp decode_batch_result(_data), do: :error

  @doc false
  @spec decode_list(term()) :: {:ok, [t()]} | :error
  def decode_list(records) when is_list(records) do
    if Enum.all?(records, &valid_record_response?/1) do
      {:ok, Enum.map(records, &from_json/1)}
    else
      :error
    end
  end

  def decode_list(_records), do: :error

  defp decode_deleted_records(records) do
    if Enum.all?(records, &match?(%{"id" => id} when is_integer(id), &1)) do
      {:ok, Enum.map(records, &struct!(DeletedRecord, id: &1["id"]))}
    else
      :error
    end
  end

  defp valid_record_response?(record) when is_map(record) do
    with %{
           "id" => id,
           "zone_id" => zone_id,
           "parent_id" => parent_id,
           "name" => name,
           "content" => content,
           "ttl" => ttl,
           "priority" => priority,
           "type" => type,
           "regions" => regions,
           "system_record" => system_record,
           "created_at" => created_at,
           "updated_at" => updated_at
         } <- record do
      is_integer(id) and is_binary(zone_id) and
        (is_nil(parent_id) or is_integer(parent_id)) and is_binary(name) and
        is_binary(content) and is_integer(ttl) and ttl >= 0 and
        (is_nil(priority) or is_integer(priority)) and type in @record_types and
        is_list(regions) and Enum.all?(regions, &(&1 in @record_regions)) and
        is_boolean(system_record) and valid_datetime?(created_at) and
        valid_datetime?(updated_at)
    else
      _missing_field -> false
    end
  end

  defp valid_record_response?(_record), do: false

  defp valid_datetime?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_datetime?(_value), do: false
end
