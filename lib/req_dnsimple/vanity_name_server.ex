defmodule ReqDnsimple.VanityNameServer do
  @moduledoc """
  DNSimple vanity name-server API functionality.

  Successful HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}`.
  Failures return `{:error, %ReqDnsimple.Error{}}`, with metadata when an
  HTTP response was received.
  Bodyless HTTP 204 responses use `nil` data.

  ## Example

      ReqDnsimple.VanityNameServer.enable(req, 1010, "example.test")
      #=> {:ok, {[%ReqDnsimple.VanityNameServer{}], %ReqDnsimple.Metadata{}}}

      ReqDnsimple.VanityNameServer.disable(req, 1010, "example.test")
      #=> {:ok, {nil, %ReqDnsimple.Metadata{}}}
  """

  # https://developer.dnsimple.com/v2/vanity/

  @type t :: %__MODULE__{
          id: integer(),
          name: binary(),
          ipv4: binary(),
          ipv6: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id name ipv4 ipv6 created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @doc """
  Uses the client's configured account. See `enable/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec enable(Req.Request.t(), binary() | integer()) :: ReqDnsimple.Response.result([t()])
  def enable(req, domain) do
    ReqDnsimple.Client.with_account(req, &enable(req, &1, domain))
  end

  @doc """
  Enables vanity name-server records for a domain by name or ID.

  This creates the domain's vanity A and AAAA records in one bodyless request
  and returns the resulting records. It does not change registrar delegation.
  DNSimple may return plan or payment errors when the feature is unavailable.
  """
  @spec enable(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          ReqDnsimple.Response.result([t()])
  def enable(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/vanity/:domain",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response}
        when is_list(data) ->
          case decode_list(data) do
            {:ok, name_servers} -> ReqDnsimple.Response.ok(name_servers, response)
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
  Uses the client's configured account. See `disable/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec disable(Req.Request.t(), binary() | integer()) :: ReqDnsimple.Response.result(nil)
  def disable(req, domain) do
    ReqDnsimple.Client.with_account(req, &disable(req, &1, domain))
  end

  @doc """
  Disables vanity name-server records for a domain by name or ID.

  This removes the vanity A and AAAA configuration in one request. It does not
  change the domain's registrar delegation or delete records individually.
  """
  @spec disable(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          ReqDnsimple.Response.result(nil)
  def disable(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/vanity/:domain",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
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

  defp decode_list(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, name_servers} ->
      case decode(item) do
        {:ok, name_server} -> {:cont, {:ok, [name_server | name_servers]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, name_servers} -> {:ok, Enum.reverse(name_servers)}
      :error -> :error
    end
  end

  defp decode(%{
         "id" => id,
         "name" => name,
         "ipv4" => ipv4,
         "ipv6" => ipv6,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_binary(name) and is_binary(ipv4) and is_binary(ipv6) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         name: name,
         ipv4: ipv4,
         ipv6: ipv6,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
