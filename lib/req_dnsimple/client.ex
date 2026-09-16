defmodule ReqDnsimple.Client do
  @moduledoc false

  @base_url "https://api.dnsimple.com/v2"
  @account_key :dnsimple_account_id

  @spec new(binary() | ReqDnsimple.token_callback(), keyword()) :: Req.Request.t()
  def new(token, opts) do
    validate_options!(opts)

    account_id =
      case Keyword.get_values(opts, :account_id) do
        [account_id] ->
          normalize_account_id!(account_id)

        [] ->
          raise ArgumentError,
                "account_id is required; use new_unscoped_client/1 for account discovery"

        _ ->
          raise ArgumentError, "account_id must be supplied exactly once"
      end

    token
    |> build(Keyword.delete(opts, :account_id))
    |> Req.Request.put_private(@account_key, account_id)
  end

  @spec new_unscoped(binary() | ReqDnsimple.token_callback(), keyword()) :: Req.Request.t()
  def new_unscoped(token, opts) do
    validate_options!(opts)

    if Keyword.has_key?(opts, :account_id) do
      raise ArgumentError, "use new_client/2 to configure an account_id"
    end

    build(token, opts)
  end

  @spec for_account(Req.Request.t(), ReqDnsimple.account_id_input()) :: Req.Request.t()
  def for_account(%Req.Request{} = req, account_id) do
    Req.Request.put_private(req, @account_key, normalize_account_id!(account_id))
  end

  @spec with_account(Req.Request.t(), (pos_integer() -> result)) ::
          result | {:error, ReqDnsimple.Error.t()}
        when result: term()
  def with_account(%Req.Request{} = req, fun) when is_function(fun, 1) do
    case Req.Request.get_private(req, @account_key) do
      nil ->
        ReqDnsimple.Response.error(:missing_account_id)

      account_id when is_integer(account_id) and account_id > 0 ->
        fun.(account_id)

      _ ->
        raise ArgumentError, "invalid client account scope; configure it with for_account/2"
    end
  end

  defp build(token, opts) when is_binary(token) do
    Req.new(base_url: @base_url, auth: {:bearer, token})
    |> ReqDnsimple.Helper.merge(opts)
  end

  defp build(token_fun, opts) when is_function(token_fun, 0) do
    Req.new(
      base_url: @base_url,
      auth: fn ->
        case token_fun.() do
          token when is_binary(token) -> {:bearer, token}
          auth -> auth
        end
      end
    )
    |> ReqDnsimple.Helper.merge(opts)
  end

  defp build(_token, _opts) do
    raise ArgumentError, "expected a token string or a zero-arity token callback"
  end

  defp validate_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "expected client options to be a keyword list"
    end
  end

  defp normalize_account_id!(account_id) when is_integer(account_id) and account_id > 0,
    do: account_id

  defp normalize_account_id!(account_id) when is_binary(account_id) do
    if Regex.match?(~r/\A[0-9]+\z/, account_id) do
      normalize_account_id!(String.to_integer(account_id))
    else
      invalid_account_id!()
    end
  end

  defp normalize_account_id!(_account_id), do: invalid_account_id!()

  defp invalid_account_id! do
    raise ArgumentError, "account_id must be a positive integer or a positive numeric string"
  end
end
