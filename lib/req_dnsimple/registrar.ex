defmodule ReqDnsimple.Registrar do
  @moduledoc """
  DNSimple registrar API functionality.

  ## Example

      ReqDnsimple.Registrar.authorize_transfer_out(req, 1010, "example.test")
      #=> :ok

      ReqDnsimple.Registrar.change_delegation(req, 1010, "example.test",
        name_servers: ["ns1.example.test", "ns2.example.test"]
      )
      #=> {:ok, ["ns1.example.test", "ns2.example.test"]}
  """

  # https://developer.dnsimple.com/v2/registrar/#authorizeDomainTransferOut

  @path_schema [
    account_id: [type: :integer, required: true],
    domain_name: [type: :string, required: true]
  ]

  @delegation_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @delegation_schema [
    name_servers: [type: {:list, :string}, required: true]
  ]

  @doc """
  Authorizes a domain transfer out.

  DNSimple unlocks the domain and emails the authorization code to the
  administrative contact. This function sends exactly one request; it does not
  retrieve the code, contact, or domain, or initiate a transfer.

  Returns `:ok` only for the API's empty HTTP 204 response. Other HTTP responses
  and transport failures are returned as explicit error tuples.
  """
  @spec authorize_transfer_out(Req.Request.t(), ReqDnsimple.account_id(), String.t()) ::
          :ok | {:error, term()}
  def authorize_transfer_out(req, account_id, domain_name) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain_name: domain_name],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/domains/:domain_name/authorize_transfer_out",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain_name: domain_name]
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
  Replaces a domain's registrar delegation.

  The required `:name_servers` option is sent as the root JSON array, including
  when it is explicitly empty. This function performs exactly one request and
  does not read, merge, or otherwise change the existing delegation first.

  Returns the ordered name-server list from a successful HTTP 200 response.
  Other HTTP responses, malformed success bodies, validation failures, and
  transport failures are returned as explicit error tuples.
  """
  @spec change_delegation(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, [String.t()]} | {:error, term()}
  def change_delegation(req, account_id, domain, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @delegation_path_schema
           ),
         {:ok, validated_attrs} <- validate_delegation_attrs(attrs) do
      req =
        Req.merge(req,
          method: :put,
          url: "/:account_id/registrar/domains/:domain/delegation",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          json: validated_attrs[:name_servers],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_name_servers(data) do
            {:ok, name_servers} -> {:ok, name_servers}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_delegation_attrs(attrs) when is_list(attrs) do
    NimbleOptions.validate(attrs, @delegation_schema)
  end

  defp validate_delegation_attrs(attrs) do
    {:error,
     %NimbleOptions.ValidationError{
       message: "expected a keyword list",
       value: attrs
     }}
  end

  defp decode_name_servers(name_servers) when is_list(name_servers) do
    if Enum.all?(name_servers, &is_binary/1), do: {:ok, name_servers}, else: :error
  end

  defp decode_name_servers(_name_servers), do: :error
end
