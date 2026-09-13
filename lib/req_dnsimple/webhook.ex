defmodule ReqDnsimple.Webhook do
  @moduledoc """
  DNSimple webhook operations.

  Register an HTTPS webhook endpoint:

      {:ok, webhook} =
        ReqDnsimple.Webhook.create(
          client,
          1010,
          url: "https://receiver.example.test/events?source=dnsimple"
        )

  Retrieve a registered webhook endpoint:

      {:ok, webhook} = ReqDnsimple.Webhook.get(client, 1010, 1)

  Deregister a webhook endpoint by numeric ID:

      :ok = ReqDnsimple.Webhook.delete(client, 1010, 1)

  These operations do not contact the callback URL, inspect deliveries, or
  discover other registrations.
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

  @doc """
  Registers an HTTPS webhook endpoint.

  The complete URL, including its path and query, is sent in one POST request.
  The callback URL is not contacted or probed.
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, t()} | {:error, term()}
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
            {:ok, webhook} -> {:ok, webhook}
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
  Retrieves a registered webhook endpoint by integer or numeric-string ID.

  A webhook's `suppressed_at` timestamp is `nil` when delivery is not
  suppressed.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), integer() | binary()) ::
          {:ok, t()} | {:error, term()}
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
            {:ok, webhook} -> {:ok, webhook}
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
  Deregisters a webhook endpoint by integer or numeric-string ID.

  Returns `:ok` only for HTTP 204.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), integer() | binary()) ::
          :ok | {:error, term()}
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
        {:ok, %Req.Response{status: 204}} ->
          :ok

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp decode(%{"id" => id, "url" => url, "suppressed_at" => suppressed_at})
       when is_integer(id) and is_binary(url) do
    with {:ok, suppressed_at} <- parse_optional_datetime(suppressed_at) do
      {:ok, %__MODULE__{id: id, url: url, suppressed_at: suppressed_at}}
    end
  end

  defp decode(_data), do: :error

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
