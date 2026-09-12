defmodule ReqDnsimple.PrimaryServer do
  @moduledoc """
  DNSimple secondary-DNS primary server API functionality.

  ## Example

      ReqDnsimple.PrimaryServer.get(req, 1010, 1)
      #=> {:ok, %ReqDnsimple.PrimaryServer{}}
  """

  # https://developer.dnsimple.com/v2/secondary-dns/#getPrimaryServer

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

  @get_schema [
    account_id: [type: :integer, required: true],
    primary_server_id: [type: :integer, required: true]
  ]

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
             @get_schema
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
