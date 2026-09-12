defmodule ReqDnsimple.PrimaryServer do
  @moduledoc """
  DNSimple secondary-DNS primary server API functionality.

  ## Example

      ReqDnsimple.PrimaryServer.create(
        req,
        1010,
        name: "Offline primary",
        ip: "192.0.2.1",
        port: 5353
      )
      #=> {:ok, %ReqDnsimple.PrimaryServer{}}

      ReqDnsimple.PrimaryServer.get(req, 1010, 1)
      #=> {:ok, %ReqDnsimple.PrimaryServer{}}

      ReqDnsimple.PrimaryServer.link(req, 1010, 1, zone: "secondary.example.test")
      #=> {:ok, %ReqDnsimple.PrimaryServer{}}

      ReqDnsimple.PrimaryServer.delete(req, 1010, 1)
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/secondary-dns/#createPrimaryServer
  # https://developer.dnsimple.com/v2/secondary-dns/#getPrimaryServer
  # https://developer.dnsimple.com/v2/secondary-dns/#linkPrimaryServer
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
      #=> {:ok, %ReqDnsimple.PrimaryServer{}}
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, t()} | {:error, term()}
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
            {:ok, primary_server} -> {:ok, primary_server}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Retrieves one secondary-DNS primary server.

  Returns the server's configured IP and port together with the ordered names
  of secondary zones linked to it.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          {:ok, t()} | {:error, term()}
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
            {:ok, primary_server} -> {:ok, primary_server}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
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
      #=> {:ok, %ReqDnsimple.PrimaryServer{}}
  """
  @spec link(Req.Request.t(), ReqDnsimple.account_id(), integer(), keyword()) ::
          {:ok, t()} | {:error, term()}
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
            {:ok, primary_server} -> {:ok, primary_server}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Deletes one secondary-DNS primary server configuration.

  The request does not unlink zones or make any DNS or reachability requests.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          :ok | {:error, term()}
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
        {:ok, %Req.Response{status: 204}} ->
          :ok

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
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

  defp valid_datetime?(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end
end
