defmodule ReqDnsimple.Certificate do
  @moduledoc """
  DNSimple certificate API functionality.

  ## Example

      ReqDnsimple.Certificate.download(req, 1010, "example.test", 202)
      #=> {:ok, %ReqDnsimple.Certificate.Download{}}
  """

  # https://developer.dnsimple.com/v2/certificates/#downloadCertificate

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
end
