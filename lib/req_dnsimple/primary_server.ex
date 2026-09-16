defmodule ReqDnsimple.PrimaryServer do
  @moduledoc """
  DNSimple secondary-DNS primary server API functionality.

  Successful HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}`.
  Failures return `{:error, %ReqDnsimple.Error{}}`, with metadata when an
  HTTP response was received.
  Bodyless HTTP 204 responses use `nil` data.

  Page pagination is nested under `metadata.pagination`. `list_all` retains
  ordered page metadata in `metadata.pages` and the latest rate-limit budget.
  Missing or malformed metadata does not invalidate resource data; diagnostics
  are in `metadata.parse_errors`. Enumeration requires usable pagination.

  ## Example

      ReqDnsimple.PrimaryServer.create(
        req,
        1010,
        name: "Offline primary",
        ip: "192.0.2.1",
        port: 5353
      )
      #=> {:ok, {%ReqDnsimple.PrimaryServer{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.PrimaryServer.get(req, 1010, 1)
      #=> {:ok, {%ReqDnsimple.PrimaryServer{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.PrimaryServer.list_page(req, 1010,
        sort: [id: :asc, name: :desc],
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.PrimaryServer{}], %ReqDnsimple.Metadata{pagination: %{"current_page" => 2}}}}

      ReqDnsimple.PrimaryServer.list_all(req, 1010, sort: [name: :asc])
      #=> {:ok, {[%ReqDnsimple.PrimaryServer{}], %ReqDnsimple.Metadata{}}}

      ReqDnsimple.PrimaryServer.link(req, 1010, 1, zone: "secondary.example.test")
      #=> {:ok, {%ReqDnsimple.PrimaryServer{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.PrimaryServer.unlink(req, 1010, 1, zone: "secondary.example.test")
      #=> {:ok, {%ReqDnsimple.PrimaryServer{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.PrimaryServer.delete(req, 1010, 1)
      #=> {:ok, {nil, %ReqDnsimple.Metadata{}}}
  """

  # https://developer.dnsimple.com/v2/secondary-dns/#createPrimaryServer
  # https://developer.dnsimple.com/v2/secondary-dns/#getPrimaryServer
  # https://developer.dnsimple.com/v2/secondary-dns/#listPrimaryServers
  # https://developer.dnsimple.com/v2/secondary-dns/#linkPrimaryServer
  # https://developer.dnsimple.com/v2/secondary-dns/#unlinkPrimaryServer
  # https://developer.dnsimple.com/v2/secondary-dns/#removePrimaryServer

  @type t :: %__MODULE__{
          id: integer(),
          account_id: ReqDnsimple.account_id(),
          name: binary(),
          ip: binary(),
          port: integer(),
          linked_secondary_zones: [binary()],
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id account_id name ip port linked_secondary_zones created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    primary_server_id: [type: :integer, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true]
  ]

  @create_schema [
    name: [type: :string, required: true],
    ip: [type: :string, required: true],
    port: [type: :integer]
  ]

  @link_schema [
    zone: [type: :string, required: true]
  ]

  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :name]]},
      doc: "Sort by id or name. Format: [id: :asc, name: :desc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of primary servers per page"]
  ]

  @doc """
  Uses the client's configured account. See `create/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec create(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result(t())
  def create(req, attrs) do
    ReqDnsimple.Client.with_account(req, &create(req, &1, attrs))
  end

  @doc """
  Creates a secondary-DNS primary server.

  `name` and `ip` are required. A supplied integer `port` is sent unchanged;
  when omitted, the API chooses its default.

  ## Example

      ReqDnsimple.PrimaryServer.create(
        req,
        1010,
        name: "Offline primary",
        ip: "192.0.2.1",
        port: 5353
      )
      #=> {:ok, {%ReqDnsimple.PrimaryServer{}, %ReqDnsimple.Metadata{}}}
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def create(req, account_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/secondary_dns/primaries",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, primary_server} -> ReqDnsimple.Response.ok(primary_server, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `get/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec get(Req.Request.t(), integer()) :: ReqDnsimple.Response.result(t())
  def get(req, primary_server_id) do
    ReqDnsimple.Client.with_account(req, &get(req, &1, primary_server_id))
  end

  @doc """
  Retrieves one secondary-DNS primary server.

  Returns the server's configured IP and port together with the ordered names
  of secondary zones linked to it.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          ReqDnsimple.Response.result(t())
  def get(req, account_id, primary_server_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, primary_server_id: primary_server_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/secondary_dns/primaries/:primary_server_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            primary_server_id: primary_server_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, primary_server} -> ReqDnsimple.Response.ok(primary_server, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_page/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_page(Req.Request.t()) :: ReqDnsimple.Response.result([t()])
  def list_page(req) do
    list_page(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result([t()])
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id()) :: ReqDnsimple.Response.result([t()])
  def list_page(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_page(req, account_id, [])
  end

  def list_page(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, opts))
  end

  @doc """
  Lists one page of secondary-DNS primary servers.

  Supports ordered `:sort` terms for `:id` and `:name`, plus `:page` and
  `:per_page`. Pagination in `metadata.pagination` retains its string keys.
  """
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id, opts) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      case request_list(req, account_id, validated_opts) do
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => data}
         } = response}
        when is_list(data) ->
          case decode_many(data) do
            {:ok, result} -> ReqDnsimple.Response.ok(result, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list(Req.Request.t()) :: ReqDnsimple.Response.result([t()])
  def list(req) do
    list(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result([t()])
  @spec list(Req.Request.t(), ReqDnsimple.account_id()) :: ReqDnsimple.Response.result([t()])
  def list(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list(req, account_id, [])
  end

  def list(req, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, opts))
  end

  @doc """
  Lists one page of secondary-DNS primary servers.

  This is a convenience alias for `list_page/3`; it never enumerates additional
  pages implicitly.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, opts), do: list_page(req, account_id, opts)

  @doc """
  Uses the client's configured account with default options.
  See `list_all/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_all(Req.Request.t()) :: ReqDnsimple.Response.result([t()])
  def list_all(req) do
    list_all(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result([t()])
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id()) :: ReqDnsimple.Response.result([t()])
  def list_all(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_all(req, account_id, [])
  end

  def list_all(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, opts))
  end

  @doc """
  Enumerates every page of secondary-DNS primary servers in server order.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. Other validated list options are retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, account_id, opts) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  @doc """
  Uses the client's configured account. See `link/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec link(Req.Request.t(), integer(), keyword()) :: ReqDnsimple.Response.result(t())
  def link(req, primary_server_id, attrs) do
    ReqDnsimple.Client.with_account(req, &link(req, &1, primary_server_id, attrs))
  end

  @doc """
  Links a secondary-DNS primary server to a secondary zone.

  `zone` is required and is sent in one request. This operation does not look
  up or create the zone or primary server.

  ## Example

      ReqDnsimple.PrimaryServer.link(
        req,
        1010,
        1,
        zone: "secondary.example.test"
      )
      #=> {:ok, {%ReqDnsimple.PrimaryServer{}, %ReqDnsimple.Metadata{}}}
  """
  @spec link(Req.Request.t(), ReqDnsimple.account_id(), integer(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def link(req, account_id, primary_server_id, attrs) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, primary_server_id: primary_server_id],
             @path_schema
           ),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @link_schema) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/secondary_dns/primaries/:primary_server_id/link",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            primary_server_id: primary_server_id
          ],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, primary_server} -> ReqDnsimple.Response.ok(primary_server, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `unlink/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec unlink(Req.Request.t(), integer(), keyword()) :: ReqDnsimple.Response.result(t())
  def unlink(req, primary_server_id, attrs) do
    ReqDnsimple.Client.with_account(req, &unlink(req, &1, primary_server_id, attrs))
  end

  @doc """
  Unlinks a secondary-DNS primary server from one secondary zone.

  `zone` is required and is sent in one request. The primary server and zone
  remain configured, and no lookup or additional mutation is performed.

  ## Example

      ReqDnsimple.PrimaryServer.unlink(
        req,
        1010,
        1,
        zone: "secondary.example.test"
      )
      #=> {:ok, {%ReqDnsimple.PrimaryServer{}, %ReqDnsimple.Metadata{}}}
  """
  @spec unlink(Req.Request.t(), ReqDnsimple.account_id(), integer(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def unlink(req, account_id, primary_server_id, attrs) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, primary_server_id: primary_server_id],
             @path_schema
           ),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @link_schema) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/secondary_dns/primaries/:primary_server_id/unlink",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            primary_server_id: primary_server_id
          ],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, primary_server} -> ReqDnsimple.Response.ok(primary_server, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `delete/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec delete(Req.Request.t(), integer()) :: ReqDnsimple.Response.result(nil)
  def delete(req, primary_server_id) do
    ReqDnsimple.Client.with_account(req, &delete(req, &1, primary_server_id))
  end

  @doc """
  Deletes one secondary-DNS primary server configuration.

  The request does not unlink zones or make any DNS or reachability requests.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          ReqDnsimple.Response.result(nil)
  def delete(req, account_id, primary_server_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, primary_server_id: primary_server_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/secondary_dns/primaries/:primary_server_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            primary_server_id: primary_server_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 204} = response} ->
          ReqDnsimple.Response.ok(nil, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Converts a primary-server response object to a typed struct.
  """
  @spec from_json(map()) :: t()
  def from_json(json) do
    ReqDnsimple.from_json(json, __MODULE__,
      regular: ~w[id account_id name ip port linked_secondary_zones],
      datetime: ~w[created_at updated_at]
    )
  end

  defp decode(
         %{
           "id" => id,
           "account_id" => account_id,
           "name" => name,
           "ip" => ip,
           "port" => port,
           "linked_secondary_zones" => linked_secondary_zones,
           "created_at" => created_at,
           "updated_at" => updated_at
         } = data
       )
       when is_integer(id) and is_integer(account_id) and is_binary(name) and is_binary(ip) and
              is_integer(port) and is_list(linked_secondary_zones) and
              is_binary(created_at) and is_binary(updated_at) do
    if Enum.all?(linked_secondary_zones, &is_binary/1) and valid_datetime?(created_at) and
         valid_datetime?(updated_at) do
      {:ok, from_json(data)}
    else
      :error
    end
  end

  defp decode(_data), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, primary_servers} ->
      case decode(item) do
        {:ok, primary_server} -> {:cont, {:ok, [primary_server | primary_servers]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, primary_servers} -> {:ok, Enum.reverse(primary_servers)}
      :error -> :error
    end
  end

  defp request_list(req, account_id, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> ReqDnsimple.Helper.merge(
      method: :get,
      url: "/:account_id/secondary_dns/primaries",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end

  defp valid_datetime?(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end
end
