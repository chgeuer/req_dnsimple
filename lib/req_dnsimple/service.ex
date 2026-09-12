defmodule ReqDnsimple.Service do
  @moduledoc """
  One-click service operations for domains.

  Apply a service with its defaults:

      :ok = ReqDnsimple.Service.apply(client, 1010, "example.test", "service-sid")

  Pass explicit string-keyed settings when the service requires them:

      :ok =
        ReqDnsimple.Service.apply(
          client,
          1010,
          "example.test",
          "service-sid",
          settings: %{"app" => "fake-app"}
        )
  """

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    service: [type: {:or, [:string, :integer]}, required: true]
  ]

  @apply_schema [
    settings: [type: :any]
  ]

  @doc """
  Applies a one-click service to a domain.

  Omitting `:settings` sends no request body. An explicitly supplied settings
  map is nested under the `settings` key and must use string keys. This sends
  exactly one request and returns `:ok` only for HTTP 204.
  """
  @spec apply(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          binary() | integer(),
          keyword()
        ) :: :ok | {:error, term()}
  def apply(req, account_id, domain, service, attrs \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, service: service],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_attrs(attrs) do
      request_options = [
        method: :post,
        url: "/:account_id/domains/:domain/services/:service",
        path_params_style: :colon,
        path_params: [account_id: account_id, domain: domain, service: service],
        retry: false
      ]

      request_options =
        if Keyword.has_key?(validated_attrs, :settings) do
          Keyword.put(request_options, :json, Map.new(validated_attrs))
        else
          request_options
        end

      req = Req.merge(req, request_options)

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

  defp validate_attrs(attrs) when is_list(attrs) do
    with {:ok, validated_attrs} <- NimbleOptions.validate(attrs, @apply_schema),
         :ok <- validate_settings(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_attrs(attrs) do
    validation_error("expected a keyword list", attrs)
  end

  defp validate_settings(attrs) do
    case Keyword.fetch(attrs, :settings) do
      :error -> :ok
      {:ok, settings} -> validate_settings_map(settings)
    end
  end

  defp validate_settings_map(settings) when is_map(settings) do
    if Enum.all?(Map.keys(settings), &is_binary/1) do
      :ok
    else
      validation_error("expected :settings to use string keys", settings)
    end
  end

  defp validate_settings_map(settings) do
    validation_error("expected :settings to be a map", settings)
  end

  defp validation_error(message, value) do
    {:error, %NimbleOptions.ValidationError{message: message, value: value}}
  end
end
