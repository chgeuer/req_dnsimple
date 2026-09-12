defmodule ReqDnsimple.Domain do
  @moduledoc """
  DNSimple Domain API functionality.

  ## Example

      ReqDnsimple.Domain.get(req, 1010, "example.test")
      #=> {:ok, %ReqDnsimple.Domain{}}

      ReqDnsimple.Domain.delete(req, 1010, "example.test")
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/domains/

  @type t :: %__MODULE__{
          id: integer(),
          account_id: ReqDnsimple.account_id(),
          registrant_id: integer() | nil,
          name: binary(),
          unicode_name: binary(),
          state: binary(),
          auto_renew: boolean(),
          private_whois: boolean(),
          expires_at: DateTime.t() | nil,
          trustee: boolean() | nil,
          expires_on: Date.t() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id account_id registrant_id name unicode_name state auto_renew private_whois
               expires_at trustee expires_on created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @doc """
  Retrieves one hosted or registered domain by name or ID.

  Registration, privacy, renewal, and expiry fields are returned without
  inferring state from nullable expiry values.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate([account_id: account_id, domain: domain], @path_schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, domain} -> {:ok, domain}
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
  Deletes one domain from an account.

  This irreversible account operation does not delete a registration at the
  registry or produce a refund.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain",
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
           "id" => id,
           "account_id" => account_id,
           "registrant_id" => registrant_id,
           "name" => name,
           "unicode_name" => unicode_name,
           "state" => state,
           "auto_renew" => auto_renew,
           "private_whois" => private_whois,
           "expires_at" => expires_at,
           "expires_on" => expires_on,
           "created_at" => created_at,
           "updated_at" => updated_at
         } = data
       )
       when is_integer(id) and is_integer(account_id) and
              (is_integer(registrant_id) or is_nil(registrant_id)) and is_binary(name) and
              is_binary(unicode_name) and state in ["hosted", "registered", "expired"] and
              is_boolean(auto_renew) and is_boolean(private_whois) do
    trustee = Map.get(data, "trustee")

    with true <- is_boolean(trustee) or is_nil(trustee),
         {:ok, expires_at} <- parse_optional_datetime(expires_at),
         {:ok, expires_on} <- parse_optional_date(expires_on),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         registrant_id: registrant_id,
         name: name,
         unicode_name: unicode_name,
         state: state,
         auto_renew: auto_renew,
         private_whois: private_whois,
         expires_at: expires_at,
         trustee: trustee,
         expires_on: expires_on,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_optional_datetime(nil), do: {:ok, nil}
  defp parse_optional_datetime(value), do: parse_datetime(value)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp parse_optional_date(nil), do: {:ok, nil}

  defp parse_optional_date(value) when is_binary(value) do
    Date.from_iso8601(value)
  end

  defp parse_optional_date(_value), do: :error
end
