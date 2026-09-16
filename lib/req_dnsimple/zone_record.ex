defmodule ReqDnsimple.ZoneRecord do
  @moduledoc """
  DNSimple Zone Record API functionality.
  Provides zone record CRUD and atomic batch operations.

  Successful HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}`.
  Failures return `{:error, %ReqDnsimple.Error{}}`, with metadata when an
  HTTP response was received.
  Bodyless HTTP 204 responses use `nil` data.

  Page pagination is nested under `metadata.pagination`. `list_all` retains
  ordered page metadata in `metadata.pages` and the latest rate-limit budget.
  Missing or malformed metadata does not invalidate resource data; diagnostics
  are in `metadata.parse_errors`. Enumeration requires usable pagination.

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

  @doc """
  Uses the client's configured account with default options.
  See `list/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list(Req.Request.t(), binary()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, zone_id) do
    list(req, zone_id, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list(Req.Request.t(), binary(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, zone_id)
      when is_integer(zone_id) or is_binary(zone_id) do
    list(req, account_id, zone_id, [])
  end

  def list(req, zone_id, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, zone_id, opts))
  end

  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, zone_id, opts) do
    list_page(req, account_id, zone_id, opts)
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_page/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_page(Req.Request.t(), binary()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  def list_page(req, zone_id) do
    list_page(req, zone_id, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(Req.Request.t(), binary(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), binary()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  def list_page(req, account_id, zone_id)
      when is_integer(zone_id) or is_binary(zone_id) do
    list_page(req, account_id, zone_id, [])
  end

  def list_page(req, zone_id, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, zone_id, opts))
  end

  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  def list_page(req, account_id, zone_id, opts) do
    # https://developer.dnsimple.com/v2/zones/records/#listZoneRecords

    with {:ok, validated_opts} <-
           ReqDnsimple.validate_options(opts, @list_zone_records_schema) do
      params =
        validated_opts
        |> ReqDnsimple.convert_sort_to_string()
        |> Map.new()

      req =
        ReqDnsimple.Helper.merge(req,
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
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          ReqDnsimple.Response.ok(Enum.map(data, &ReqDnsimple.ZoneRecord.from_json/1), response)

        {:ok, %Req.Response{status: 404} = response} ->
          ReqDnsimple.Response.error(:not_found, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, e} ->
          ReqDnsimple.Response.error(e)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_all/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_all(Req.Request.t(), binary()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  def list_all(req, zone_id) do
    list_all(req, zone_id, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), binary(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  def list_all(req, account_id, zone_id)
      when is_integer(zone_id) or is_binary(zone_id) do
    list_all(req, account_id, zone_id, [])
  end

  def list_all(req, zone_id, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, zone_id, opts))
  end

  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          ReqDnsimple.Response.result([ReqDnsimple.ZoneRecord.t()])
  def list_all(req, account_id, zone_id, opts) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, zone_id, &1))
  end

  @doc """
  Uses the client's configured account. See `get/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec get(
          Req.Request.t(),
          ReqDnsimple.zone_name(),
          ReqDnsimple.record_id()
        ) :: ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  def get(req, zone_name, record_id) do
    ReqDnsimple.Client.with_account(req, &get(req, &1, zone_name, record_id))
  end

  @spec get(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name(),
          ReqDnsimple.record_id()
        ) :: ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
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
      {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
        ReqDnsimple.Response.ok(ReqDnsimple.ZoneRecord.from_json(data), response)

      {:ok, %Req.Response{status: 404} = response} ->
        ReqDnsimple.Response.error(:not_found, response)

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        ReqDnsimple.Response.error(e)
    end
  end

  @check_distribution_schema [
    account_id: [type: :integer, required: true],
    zone_name: [type: :string, required: true],
    record_id: [type: :integer, required: true]
  ]

  @doc """
  Uses the client's configured account. See `check_distribution/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec check_distribution(
          Req.Request.t(),
          ReqDnsimple.zone_name(),
          ReqDnsimple.record_id()
        ) :: ReqDnsimple.Response.result(boolean())
  def check_distribution(req, zone_name, record_id) do
    ReqDnsimple.Client.with_account(req, &check_distribution(req, &1, zone_name, record_id))
  end

  @doc """
  Checks whether an individual zone record is distributed to all name servers.

  ## Example

      ReqDnsimple.ZoneRecord.check_distribution(req, 1010, "example.test", 1)
      #=> {:ok, {true, %ReqDnsimple.Metadata{}}}
  """
  @spec check_distribution(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name(),
          ReqDnsimple.record_id()
        ) :: ReqDnsimple.Response.result(boolean())
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
         } = response}
        when is_boolean(distributed) ->
          ReqDnsimple.Response.ok(distributed, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @integrated_zones_schema [
    type: {:list, {:or, [:integer, {:in, ["dnsimple"]}]}},
    doc: ~s(Target integrated-zone IDs and/or "dnsimple" for the DNSimple zone)
  ]

  @zone_record_schema [
    name: [type: :string, required: true, doc: ~s(Name relative to the zone; use "" for the apex)],
    type: [type: :string, required: true, doc: "Record type (A, AAAA, CNAME, MX, etc.)"],
    content: [
      type: :string,
      required: true,
      doc: "Record value in the format expected by its type"
    ],
    ttl: [type: :non_neg_integer, doc: "Time-to-live in seconds"],
    priority: [
      type: {:or, [:non_neg_integer, {:in, [nil]}]},
      doc: "Record priority, for example for MX or SRV records; nil sends JSON null"
    ],
    regions: [type: {:list, :string}, doc: ~s(Geographical regions, such as ["global"])],
    integrated_zones: @integrated_zones_schema
  ]

  @create_doc """
  Creates a DNS record in the zone named by `zone_id`.

  The three-argument form uses the client's configured account and returns
  a `ReqDnsimple.Error` with reason `:missing_account_id` without HTTP when it is unscoped. The
  four-argument form uses an explicit account for this call only.

  `attrs` must be a keyword list. The `:name`, `:type`, and `:content` attributes
  are required. Optional attributes are omitted from the request unless supplied;
  explicit zero values for `:ttl` and `:priority` are preserved. An explicit
  `priority: nil` is sent as JSON `null`.

  Returns `{:ok, {%ReqDnsimple.ZoneRecord{}, %ReqDnsimple.Metadata{}}}` or `{:error, %ReqDnsimple.Error{reason: reason}}`.
  `ReqDnsimple.create_zone_record/3` and `ReqDnsimple.create_zone_record/4`
  are the equivalent top-level helpers.

  ## Options

  #{NimbleOptions.docs(@zone_record_schema)}

  ## Example

      ReqDnsimple.ZoneRecord.create(client, "example.com",
        name: "www",
        type: "A",
        content: "192.0.2.1",
        ttl: 300
      )
  """
  @doc @create_doc
  @spec create(Req.Request.t(), binary(), keyword()) ::
          ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  def create(req, zone_id, attrs) do
    ReqDnsimple.Client.with_account(req, &create(req, &1, zone_id, attrs))
  end

  @doc @create_doc
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), binary(), keyword()) ::
          ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  def create(req, account_id, zone_id, attrs) do
    # https://developer.dnsimple.com/v2/zones/records/#createZoneRecord

    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @zone_record_schema) do
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
        {:ok, %Req.Response{status: status, body: body} = response} ->
          case {status, body} do
            {201, %{"data" => data}} ->
              ReqDnsimple.Response.ok(ReqDnsimple.ZoneRecord.from_json(data), response)

            {200, %{"data" => data}} ->
              ReqDnsimple.Response.ok(ReqDnsimple.ZoneRecord.from_json(data), response)

            {404, _} ->
              ReqDnsimple.Response.error(:not_found, response)

            {400, %{"errors" => errors, "message" => message}} ->
              ReqDnsimple.Response.error(
                %{status: 400, message: message, errors: errors},
                response
              )

            {_status, _} ->
              ReqDnsimple.response_error(response)
          end

        {:error, e} ->
          ReqDnsimple.Response.error(e)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `delete/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec delete(Req.Request.t(), binary(), integer()) :: ReqDnsimple.Response.result(nil)
  def delete(req, zone_id, record_id) do
    ReqDnsimple.Client.with_account(req, &delete(req, &1, zone_id, record_id))
  end

  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary(), integer()) ::
          ReqDnsimple.Response.result(nil)
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
      {:ok, %Req.Response{status: 204} = response} ->
        ReqDnsimple.Response.ok(nil, response)

      {:ok, %Req.Response{status: 404} = response} ->
        ReqDnsimple.Response.error(:not_found, response)

      {:ok, response} ->
        ReqDnsimple.response_error(response)

      {:error, e} ->
        ReqDnsimple.Response.error(e)
    end
  end

  @update_zone_record_schema [
    name: [type: :string, doc: "Record name without domain"],
    content: [type: :string, doc: "Record content"],
    ttl: [type: :non_neg_integer, doc: "Time-to-live in seconds"],
    priority: [
      type: {:or, [:non_neg_integer, {:in, [nil]}]},
      doc: "Priority (for MX records); nil sends JSON null"
    ],
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

  @batch_change_path_schema [
    account_id: [type: :integer, required: true],
    zone_name: [type: :string, required: true]
  ]

  @doc """
  Uses the client's configured account. See `batch_change/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec batch_change(
          Req.Request.t(),
          ReqDnsimple.zone_name(),
          keyword()
        ) :: ReqDnsimple.Response.result(BatchResult.t())
  def batch_change(req, zone_name, attrs) do
    ReqDnsimple.Client.with_account(req, &batch_change(req, &1, zone_name, attrs))
  end

  @spec batch_change(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          ReqDnsimple.zone_name(),
          keyword()
        ) :: ReqDnsimple.Response.result(BatchResult.t())
  def batch_change(req, account_id, zone_name, attrs) do
    with {:ok, attrs} <- ReqDnsimple.validate_keyword_list(attrs),
         {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, zone_name: zone_name],
             @batch_change_path_schema
           ),
         {:ok, validated_attrs} <- NimbleOptions.validate(attrs, @batch_change_schema) do
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
            {:ok, result} -> ReqDnsimple.Response.ok(result, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok,
         %Req.Response{
           status: 400,
           body: %{"message" => message, "errors" => errors}
         } = response}
        when is_binary(message) and is_map(errors) ->
          ReqDnsimple.Response.error(%{status: 400, message: message, errors: errors}, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `update/5` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec update(
          Req.Request.t(),
          binary(),
          ReqDnsimple.record_id(),
          keyword()
        ) :: ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  def update(req, zone_id, record_id, attrs) do
    ReqDnsimple.Client.with_account(req, &update(req, &1, zone_id, record_id, attrs))
  end

  @doc """
  Updates the DNS record identified by `record_id` in the zone named by `zone_id`.

  `attrs` must be a keyword list. Only supplied attributes are sent; omitted
  fields remain absent. Explicit zero values for `:ttl` and `:priority` are
  preserved, and `priority: nil` is sent as JSON `null`.

  Returns `{:ok, {%ReqDnsimple.ZoneRecord{}, %ReqDnsimple.Metadata{}}}` or `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Options

  #{NimbleOptions.docs(@update_zone_record_schema)}
  """
  @spec update(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary(),
          ReqDnsimple.record_id(),
          keyword()
        ) :: ReqDnsimple.Response.result(ReqDnsimple.ZoneRecord.t())
  def update(req, account_id, zone_id, record_id, attrs) do
    # https://developer.dnsimple.com/v2/zones/records/#updateZoneRecord

    with {:ok, validated_attrs} <-
           ReqDnsimple.validate_options(attrs, @update_zone_record_schema) do
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
        {:ok, %Req.Response{status: status, body: body} = response} ->
          case {status, body} do
            {200, %{"data" => data}} ->
              ReqDnsimple.Response.ok(ReqDnsimple.ZoneRecord.from_json(data), response)

            {404, _} ->
              ReqDnsimple.Response.error(:not_found, response)

            {400, %{"errors" => errors, "message" => message}} ->
              ReqDnsimple.Response.error(
                %{status: 400, message: message, errors: errors},
                response
              )

            {_status, _} ->
              ReqDnsimple.response_error(response)
          end

        {:error, e} ->
          ReqDnsimple.Response.error(e)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
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
