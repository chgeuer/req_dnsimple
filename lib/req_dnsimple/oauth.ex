defmodule ReqDnsimple.OAuth do
  @moduledoc """
  DNSimple OAuth authorization URLs and token exchange.

  Applications must supply an unguessable state and verify it on return.
  The pure URL builder does not generate, store, or verify state.

  Prepare an authorization URL for a public client using PKCE:

      verifier = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      challenge = :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)

      {:ok, url} =
        ReqDnsimple.OAuth.authorize_url(client, "fake-offline-client",
          code_challenge: challenge,
          code_challenge_method: "S256",
          redirect_uri: "http://127.0.0.1:54321/callback",
          state: state
        )

  Redirect the user to `url`, verify the returned state, and exchange the
  authorization code using the original verifier:

      {:ok, {token, metadata}} =
        ReqDnsimple.OAuth.exchange_code(client,
          client_id: "fake-offline-client",
          code: "fake-offline-code",
          grant_type: "authorization_code",
          code_verifier: verifier,
          redirect_uri: "http://127.0.0.1:54321/callback",
          state: state
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

  @authorize_schema [
    state: [type: :string],
    redirect_uri: [type: :string],
    account_id: [type: :non_neg_integer],
    code_challenge: [type: :string],
    code_challenge_method: [type: {:in, ["S256"]}]
  ]

  @pkce_challenge ~r/\A[A-Za-z0-9_-]{43}\z/
  @authorize_hostname ~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\.?\z/

  @doc """
  Builds an OAuth authorization URL without optional parameters.

  Returns `{:ok, url}` or `{:error, %NimbleOptions.ValidationError{}}`.
  This is a pure local operation: it does not send HTTP, evaluate callbacks,
  discover accounts, or modify the request. See `authorize_url/3` for origin
  handling and options. Applications must supply a fresh, unguessable `:state`
  through `authorize_url/3` and verify it on return. State remains optional in
  this builder for compatibility; it is not generated, stored, or verified.
  Public clients must also supply PKCE parameters.

  ## Example

      ReqDnsimple.OAuth.authorize_url(client, "offline-client")
      #=> {:ok, "https://app.dnsimple.com/oauth/authorize?response_type=code&client_id=offline-client"}
  """
  @spec authorize_url(Req.Request.t(), binary()) ::
          {:ok, binary()} | {:error, NimbleOptions.ValidationError.t()}
  def authorize_url(req, client_id), do: authorize_url(req, client_id, [])

  @doc """
  Builds an OAuth authorization URL with optional query parameters.

  `client_id` must be a nonempty string. `response_type=code` is always set and
  cannot be overridden. Supported keyword options are:

    * `:state` - applications must supply a fresh, unguessable string and
      verify it on return for CSRF protection.
    * `:redirect_uri` - the registered callback URI, encoded as a query value.
    * `:account_id` - a non-negative integer selecting a preferred account.
      The client's selected account is never inherited.
    * `:code_challenge` - the 43-character base64url-encoded SHA-256 digest
      of the PKCE verifier. Required for public clients.
    * `:code_challenge_method` - `"S256"`, required together with
      `:code_challenge`. Other methods are not supported.

  Omitted options stay omitted; explicit empty `:state` and `:redirect_uri`
  strings are preserved for compatibility. This builder does not generate,
  store, or verify state. The caller retains the verifier for `exchange_code/2`;
  `:code_verifier`, `:client_secret`, duplicate options, and unknown options
  are rejected.

  The request's static `:base_url` must be an absolute HTTP(S) string or `URI`
  with an ASCII DNS hostname or IP address and no user information.
  `api.dnsimple.com` maps case-insensitively to `app.dnsimple.com`;
  `api.sandbox.dnsimple.com` maps to `sandbox.dnsimple.com`. For custom origins,
  only a leading `api.` hostname label is removed. HTTP(S) schemes and ports
  are preserved. The path is replaced with `/oauth/authorize`; existing base paths,
  queries, and fragments are discarded. Missing or dynamic base URLs and
  unsupported origins return validation errors, never a production fallback.

  Returns `{:ok, url}` or `{:error, %NimbleOptions.ValidationError{}}` without
  sending HTTP, evaluating credentials or request steps, discovering accounts,
  or modifying scoped or unscoped clients.

  ## Example

      ReqDnsimple.OAuth.authorize_url(client, "offline-client", state: "offline-state")
      #=> {:ok, "https://app.dnsimple.com/oauth/authorize?response_type=code&client_id=offline-client&state=offline-state"}
  """
  @spec authorize_url(Req.Request.t(), binary(), keyword()) ::
          {:ok, binary()} | {:error, NimbleOptions.ValidationError.t()}
  def authorize_url(%Req.Request{} = req, client_id, opts)
      when is_binary(client_id) and byte_size(client_id) > 0 do
    with {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @authorize_schema),
         :ok <- validate_authorize_options(opts),
         {:ok, uri} <- authorize_origin(Req.Request.get_option(req, :base_url)) do
      query = URI.encode_query([response_type: "code", client_id: client_id] ++ validated_opts)
      {:ok, URI.to_string(%{uri | query: query})}
    end
  end

  def authorize_url(%Req.Request{}, client_id, _opts) do
    validation_error("expected :client_id to be a nonempty string", client_id)
  end

  def authorize_url(req, _client_id, _opts) do
    validation_error("expected :req to be a Req.Request", req)
  end

  @doc """
  Exchanges an OAuth authorization code for a typed access token.

  `:client_id`, `:code`, and `grant_type: "authorization_code"` are required.
  Supply at least one of `:client_secret` for a confidential client or a
  43-128 character RFC 7636 `:code_verifier` for a public client. Optional
  `:redirect_uri` and `:state` values are forwarded unchanged.

  The response is `{:ok, {%ReqDnsimple.OAuth.Token{}, %ReqDnsimple.Metadata{}}}` for HTTP 200 or
  `{:error, %ReqDnsimple.Error{}}` for validation, HTTP, transport, or decoding failures.
  Errors preserve their original reason in `error.reason`. Validation and
  transport failures have `nil` metadata; HTTP and decoding failures retain
  the actual response metadata in `error.metadata`.
  """
  @spec exchange_code(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result(Token.t())
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
            {:ok, token} -> ReqDnsimple.Response.ok(token, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  defp validate_authorize_options(opts) do
    keys = Keyword.keys(opts)

    if length(keys) == length(Enum.uniq(keys)) do
      validate_authorize_pkce(opts)
    else
      validation_error("expected each authorization option to be supplied at most once", opts)
    end
  end

  defp validate_authorize_pkce(opts) do
    case {Keyword.fetch(opts, :code_challenge), Keyword.fetch(opts, :code_challenge_method)} do
      {:error, :error} ->
        :ok

      {{:ok, challenge}, {:ok, "S256"}} ->
        if Regex.match?(@pkce_challenge, challenge) do
          :ok
        else
          validation_error(
            "expected :code_challenge to be a 43-character base64url digest",
            challenge
          )
        end

      _incomplete ->
        validation_error(
          "expected :code_challenge and code_challenge_method: \"S256\" together",
          opts
        )
    end
  end

  defp authorize_origin(base_url) do
    with {:ok, %URI{scheme: scheme, host: host, port: port, userinfo: nil}} <-
           parse_authorize_origin(base_url),
         true <- is_binary(scheme) and is_binary(host),
         scheme = String.downcase(scheme, :ascii),
         true <- scheme in ["http", "https"],
         true <- is_nil(port) or (is_integer(port) and port in 1..65_535),
         host = host |> String.downcase(:ascii) |> authorize_host(),
         true <- valid_authorize_host?(host) do
      {:ok, %URI{scheme: scheme, host: host, port: port, path: "/oauth/authorize"}}
    else
      _invalid ->
        validation_error(
          "expected :base_url to be a static absolute HTTP(S) URI with a valid host and port and no user information",
          base_url
        )
    end
  end

  defp parse_authorize_origin(base_url) when is_binary(base_url), do: URI.new(base_url)
  defp parse_authorize_origin(%URI{} = base_url), do: {:ok, base_url}
  defp parse_authorize_origin(_base_url), do: :error

  defp authorize_host("api.dnsimple.com"), do: "app.dnsimple.com"
  defp authorize_host(host), do: String.replace_prefix(host, "api.", "")

  defp valid_authorize_host?(host) do
    Regex.match?(@authorize_hostname, host) or
      match?({:ok, _address}, :inet.parse_address(:binary.bin_to_list(host)))
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
