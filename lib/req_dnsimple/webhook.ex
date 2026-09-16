defmodule ReqDnsimple.Webhook do
  @moduledoc """
  DNSimple webhook operations.

  HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
  `{:error, %ReqDnsimple.Error{}}`. HTTP 204 successes have `nil` data.
  Errors preserve their original reason in `error.reason`. When no response
  has been received, `error.metadata` is `nil`.

  Register an HTTPS webhook endpoint:

      {:ok, {webhook, metadata}} =
        ReqDnsimple.Webhook.create(
          client,
          1010,
          url: "https://receiver.example.test/events?source=dnsimple"
        )

  Retrieve a registered webhook endpoint:

      {:ok, {webhook, metadata}} = ReqDnsimple.Webhook.get(client, 1010, 1)

  List registered webhook endpoints:

      {:ok, {webhooks, metadata}} =
        ReqDnsimple.Webhook.list(client, 1010, sort: [id: :asc])

  Deregister a webhook endpoint by numeric ID:

      {:ok, {nil, metadata}} = ReqDnsimple.Webhook.delete(client, 1010, 1)

  These operations do not contact the callback URL, inspect deliveries, or
  perform hidden follow-up requests.
  """

  @type t :: %__MODULE__{
          id: integer(),
          url: binary(),
          suppressed_at: DateTime.t() | nil
        }

  defstruct ~w(id url suppressed_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    webhook_id: [type: {:or, [:integer, :string]}, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true]
  ]

  @create_schema [
    url: [type: :string, required: true]
  ]

  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id]]},
      doc: "Sort by id. Format: [id: :asc]"
    ]
  ]

  @doc """
  Uses the client's configured account with default options.
  See `list/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list(Req.Request.t()) ::
          ReqDnsimple.Response.result([t()])
  def list(req) do
    list(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list(req, account_id, [])
  end

  def list(req, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, opts))
  end

  @doc """
  Lists registered webhook endpoints.

  Supports ordered `:sort` terms for `:id`. This endpoint is not paginated and
  returns the complete `data` array without synthetic pagination metadata.

  ## Example

      ReqDnsimple.Webhook.list(req, 1010, sort: [id: :asc])
      #=> {:ok, {[%ReqDnsimple.Webhook{}], %ReqDnsimple.Metadata{}}}
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, opts) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      req =
        ReqDnsimple.Helper.merge(req,
          method: :get,
          url: "/:account_id/webhooks",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          params: ReqDnsimple.convert_sort_to_string(validated_opts)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_list(data) do
            {:ok, webhooks} -> ReqDnsimple.Response.ok(webhooks, response)
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

  @doc """
  Uses the client's configured account. See `create/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec create(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def create(req, attrs) do
    ReqDnsimple.Client.with_account(req, &create(req, &1, attrs))
  end

  @doc """
  Registers an HTTPS webhook endpoint.

  The complete URL, including its path and query, is sent in one POST request.
  The callback URL is not contacted or probed.
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def create(req, account_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema),
         :ok <- validate_https_url(validated_attrs[:url]) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/webhooks",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, webhook} -> ReqDnsimple.Response.ok(webhook, response)
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

  @doc """
  Uses the client's configured account. See `get/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec get(Req.Request.t(), integer() | binary()) ::
          ReqDnsimple.Response.result(t())
  def get(req, webhook_id) do
    ReqDnsimple.Client.with_account(req, &get(req, &1, webhook_id))
  end

  @doc """
  Retrieves a registered webhook endpoint by integer or numeric-string ID.

  A webhook's `suppressed_at` timestamp is `nil` when delivery is not
  suppressed.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), integer() | binary()) ::
          ReqDnsimple.Response.result(t())
  def get(req, account_id, webhook_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, webhook_id: webhook_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/webhooks/:webhook_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, webhook_id: webhook_id]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, webhook} -> ReqDnsimple.Response.ok(webhook, response)
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

  @doc """
  Uses the client's configured account. See `delete/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec delete(Req.Request.t(), integer() | binary()) ::
          ReqDnsimple.Response.result(nil)
  def delete(req, webhook_id) do
    ReqDnsimple.Client.with_account(req, &delete(req, &1, webhook_id))
  end

  @doc """
  Deregisters a webhook endpoint by integer or numeric-string ID.

  Returns `{:ok, {nil, metadata}}` only for HTTP 204.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), integer() | binary()) ::
          ReqDnsimple.Response.result(nil)
  def delete(req, account_id, webhook_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, webhook_id: webhook_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/webhooks/:webhook_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, webhook_id: webhook_id],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 204} = response} ->
          ReqDnsimple.Response.ok(nil, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  defp decode(%{"id" => id, "url" => url, "suppressed_at" => suppressed_at})
       when is_integer(id) and is_binary(url) do
    with {:ok, suppressed_at} <- parse_optional_datetime(suppressed_at) do
      {:ok, %__MODULE__{id: id, url: url, suppressed_at: suppressed_at}}
    end
  end

  defp decode(_data), do: :error

  defp decode_list(data) when is_list(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, webhooks} ->
      case decode(item) do
        {:ok, webhook} -> {:cont, {:ok, [webhook | webhooks]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, webhooks} -> {:ok, Enum.reverse(webhooks)}
      :error -> :error
    end
  end

  defp decode_list(_data), do: :error

  defp validate_https_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" ->
        :ok

      _invalid ->
        {:error,
         %NimbleOptions.ValidationError{
           message: "expected :url to be an absolute HTTPS URI",
           key: :url,
           value: url
         }}
    end
  end

  defp parse_optional_datetime(nil), do: {:ok, nil}

  defp parse_optional_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_optional_datetime(_value), do: :error
end
