defmodule ReqDnsimple.Dnssec do
  @moduledoc """
  Operations for domain DNSSEC.

  Retrieve a domain's DNSSEC status:

      {:ok, dnssec} = ReqDnsimple.Dnssec.get(client, 1010, "example.test")

  Enable DNSSEC for a domain:

      {:ok, dnssec} = ReqDnsimple.Dnssec.enable(client, 1010, "example.test")

  Disable DNSSEC for a domain:

      :ok = ReqDnsimple.Dnssec.disable(client, 1010, "example.test")

  For domains registered with DNSimple, DNSimple submits the delegation-signer
  records to the registry. Hosted-only domains require the caller to coordinate
  delegation-signer records with the registrar.

  For hosted-only domains, remove registry delegation-signer records before
  disabling DNSSEC. This operation does not remove those records automatically.
  """

  @type t :: %__MODULE__{
          enabled: boolean(),
          active: boolean() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(enabled active created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @doc """
  Retrieves a domain's DNSSEC status.

  The enabled and active states are returned separately, along with the
  timestamps supplied by DNSimple. The optional active state is `nil` when the
  API omits it.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate([account_id: account_id, domain: domain], @path_schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/dnssec",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, dnssec} -> {:ok, dnssec}
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
  Enables DNSSEC for a domain.

  Returns the DNSSEC state immediately after DNSimple accepts the request. For
  domains registered with DNSimple, DNSimple handles registry delegation-signer
  submission. Hosted-only domains require caller-managed registrar coordination.
  """
  @spec enable(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, t()} | {:error, term()}
  def enable(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate([account_id: account_id, domain: domain], @path_schema) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/dnssec",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, dnssec} -> {:ok, dnssec}
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
  Disables DNSSEC for a domain.

  Returns `:ok` only for the API's empty HTTP 204 response. HTTP 428 when DNSSEC
  is not currently enabled, other HTTP responses, and transport failures are
  returned as explicit error tuples.
  """
  @spec disable(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def disable(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/dnssec",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
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

  defp decode(
         %{
           "enabled" => enabled,
           "created_at" => created_at,
           "updated_at" => updated_at
         } = data
       )
       when is_boolean(enabled) do
    active = Map.get(data, "active")

    with true <- is_boolean(active) or not Map.has_key?(data, "active"),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         enabled: enabled,
         active: active,
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
