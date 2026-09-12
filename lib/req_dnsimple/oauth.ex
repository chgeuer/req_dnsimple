defmodule ReqDnsimple.OAuth do
  @moduledoc """
  DNSimple OAuth token exchange.

  Exchange an authorization code for a public client using PKCE:

      {:ok, token} =
        ReqDnsimple.OAuth.exchange_code(client,
          client_id: "fake-offline-client",
          code: "fake-offline-code",
          grant_type: "authorization_code",
          code_verifier: String.duplicate("a", 43),
          redirect_uri: "http://127.0.0.1:54321/callback",
          state: "fake-offline-state"
        )

  Confidential clients supply `:client_secret` instead of `:code_verifier`.
  The exchange removes inherited authorization credentials and does not invoke
  dynamic bearer-token callbacks.
  """

  defmodule Token do
    @moduledoc """
    An OAuth access token returned by DNSimple.
    """

    @type t :: %__MODULE__{
            access_token: binary(),
            token_type: binary(),
            scope: binary() | nil,
            account_id: integer()
          }

    defstruct ~w(access_token token_type scope account_id)a
  end

  @attrs_schema [
    client_id: [type: :string, required: true],
    client_secret: [type: :string],
    code: [type: :string, required: true],
    grant_type: [type: {:in, ["authorization_code"]}, required: true],
    redirect_uri: [type: :string],
    state: [type: :string],
    code_verifier: [type: :string]
  ]

  @pkce_verifier ~r/\A[A-Za-z0-9._~-]{43,128}\z/

  @doc """
  Exchanges an OAuth authorization code for a typed access token.

  `:client_id`, `:code`, and `grant_type: "authorization_code"` are required.
  Supply at least one of `:client_secret` for a confidential client or a
  43-128 character RFC 7636 `:code_verifier` for a public client. Optional
  `:redirect_uri` and `:state` values are forwarded unchanged.

  The response is `{:ok, %ReqDnsimple.OAuth.Token{}}` for HTTP 200 or
  `{:error, reason}` for validation, HTTP, transport, or decoding failures.
  """
  @spec exchange_code(Req.Request.t(), keyword()) :: {:ok, Token.t()} | {:error, term()}
  def exchange_code(req, attrs) do
    with {:ok, validated_attrs} <- validate_attrs(attrs) do
      req =
        req
        |> Req.Request.delete_option(:auth)
        |> Req.Request.delete_header("authorization")
        |> Req.merge(
          method: :post,
          url: "/oauth/access_token",
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: data} = response} ->
          case decode(data) do
            {:ok, token} -> {:ok, token}
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp validate_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @attrs_schema),
         :ok <- validate_credentials(validated_attrs),
         :ok <- validate_code_verifier(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_credentials(attrs) do
    if Keyword.has_key?(attrs, :client_secret) or Keyword.has_key?(attrs, :code_verifier) do
      :ok
    else
      validation_error("expected :client_secret or :code_verifier", attrs)
    end
  end

  defp validate_code_verifier(attrs) do
    case Keyword.fetch(attrs, :code_verifier) do
      :error ->
        :ok

      {:ok, code_verifier} ->
        if Regex.match?(@pkce_verifier, code_verifier) do
          :ok
        else
          validation_error(
            "expected :code_verifier to be 43-128 RFC 7636 unreserved ASCII characters",
            code_verifier
          )
        end
    end
  end

  defp decode(%{
         "access_token" => access_token,
         "token_type" => token_type,
         "scope" => scope,
         "account_id" => account_id
       })
       when is_binary(access_token) and is_binary(token_type) and
              (is_binary(scope) or is_nil(scope)) and is_integer(account_id) do
    {:ok,
     %Token{
       access_token: access_token,
       token_type: token_type,
       scope: scope,
       account_id: account_id
     }}
  end

  defp decode(_data), do: :error

  defp validation_error(message, value) do
    {:error, %NimbleOptions.ValidationError{message: message, value: value}}
  end
end
