defmodule ReqDnsimple.Certificate do
  @moduledoc """
  DNSimple certificate API functionality.

  ## Example

      ReqDnsimple.Certificate.get(req, 1010, "example.test", 202)
      #=> {:ok, %ReqDnsimple.Certificate{}}

      ReqDnsimple.Certificate.download(req, 1010, "example.test", 202)
      #=> {:ok, %ReqDnsimple.Certificate.Download{}}
  """

  # https://developer.dnsimple.com/v2/certificates/

  @type t :: %__MODULE__{
          id: integer(),
          domain_id: integer(),
          name: binary(),
          common_name: binary(),
          years: integer(),
          csr: binary() | nil,
          state: binary(),
          auto_renew: boolean(),
          alternate_names: [binary()],
          authority_identifier: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          expires_at: DateTime.t() | nil,
          expires_on: Date.t() | nil,
          contact_id: integer() | nil
        }

  defstruct ~w(id domain_id name common_name years csr state auto_renew alternate_names
               authority_identifier created_at updated_at expires_at expires_on contact_id)a

  defmodule Download do
    @moduledoc """
    A certificate's PEM-encoded server, root, and intermediate certificates.
    """

    @type t :: %__MODULE__{
            server: binary(),
            root: binary() | nil,
            chain: [binary()]
          }

    defstruct [:server, :root, chain: []]
  end

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    certificate_id: [type: :integer, required: true]
  ]

  @doc """
  Retrieves certificate metadata by account, domain name or ID, and certificate ID.

  Pending certificates preserve nullable CSR and expiry fields. Issued
  certificate expiry timestamps and dates are decoded to their Elixir types.
  """
  @spec get(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain, certificate_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/certificates/:certificate_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            certificate_id: certificate_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, certificate} -> {:ok, certificate}
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
  Downloads a certificate's PEM bundle without writing it to the filesystem.

  The PEM strings are returned byte-for-byte as supplied by DNSimple. A
  certificate that is not yet downloadable returns the API's HTTP 428 error.
  """
  @spec download(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) ::
          {:ok, Download.t()} | {:error, term()}
  def download(req, account_id, domain, certificate_id) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               domain: domain,
               certificate_id: certificate_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/certificates/:certificate_id/download",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            certificate_id: certificate_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_download(data) do
            {:ok, download} -> {:ok, download}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp decode_download(%{"server" => server, "root" => root, "chain" => chain})
       when is_binary(server) and (is_binary(root) or is_nil(root)) and is_list(chain) do
    if Enum.all?(chain, &is_binary/1) do
      {:ok, %Download{server: server, root: root, chain: chain}}
    else
      :error
    end
  end

  defp decode_download(_data), do: :error

  defp decode(
         %{
           "id" => id,
           "domain_id" => domain_id,
           "name" => name,
           "common_name" => common_name,
           "years" => years,
           "csr" => csr,
           "state" => state,
           "auto_renew" => auto_renew,
           "alternate_names" => alternate_names,
           "authority_identifier" => authority_identifier,
           "created_at" => created_at,
           "updated_at" => updated_at,
           "expires_at" => expires_at,
           "expires_on" => expires_on
         } = data
       )
       when is_integer(id) and is_integer(domain_id) and is_binary(name) and
              is_binary(common_name) and is_integer(years) and
              (is_binary(csr) or is_nil(csr)) and
              state in [
                "new",
                "purchased",
                "configured",
                "submitted",
                "issued",
                "rejected",
                "refunded",
                "cancelled",
                "requesting",
                "failed"
              ] and is_boolean(auto_renew) and is_list(alternate_names) and
              authority_identifier in ["comodo", "rapidssl", "letsencrypt"] do
    contact_id = Map.get(data, "contact_id")

    with true <- Enum.all?(alternate_names, &is_binary/1),
         true <- is_integer(contact_id) or is_nil(contact_id),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at),
         {:ok, expires_at} <- parse_optional_datetime(expires_at),
         {:ok, expires_on} <- parse_optional_date(expires_on) do
      {:ok,
       %__MODULE__{
         id: id,
         domain_id: domain_id,
         name: name,
         common_name: common_name,
         years: years,
         csr: csr,
         state: state,
         auto_renew: auto_renew,
         alternate_names: alternate_names,
         authority_identifier: authority_identifier,
         created_at: created_at,
         updated_at: updated_at,
         expires_at: expires_at,
         expires_on: expires_on,
         contact_id: contact_id
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
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parse_optional_date(_value), do: :error
end
