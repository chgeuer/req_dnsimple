defmodule ReqDnsimple.Service do
  @moduledoc """
  One-click service catalog and domain operations.

  Retrieve a global service definition by sid or ID:

      {:ok, service} = ReqDnsimple.Service.get(client, "service-sid")

  List one page of services applied to a domain, including pagination:

      {:ok, {services, pagination}} =
        ReqDnsimple.Service.list_page_applied(client, 1010, "example.test", per_page: 30)

  Explicitly enumerate every applied service:

      {:ok, services} =
        ReqDnsimple.Service.list_all_applied(client, 1010, "example.test", per_page: 30)

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

  Unapply one selected service without deleting records individually:

      :ok = ReqDnsimple.Service.unapply(client, 1010, "example.test", "service-sid")
  """

  defmodule Setting do
    @moduledoc """
    A configurable field required by a one-click service.
    """

    @type t :: %__MODULE__{
            name: binary(),
            label: binary(),
            append: binary() | nil,
            description: binary(),
            example: binary() | nil,
            password: boolean()
          }

    defstruct ~w(name label append description example password)a
  end

  @type t :: %__MODULE__{
          id: integer(),
          name: binary(),
          sid: binary(),
          description: binary(),
          setup_description: binary() | nil,
          requires_setup: boolean(),
          default_subdomain: binary() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          settings: [Setting.t()]
        }

  defstruct ~w(
    id
    name
    sid
    description
    setup_description
    requires_setup
    default_subdomain
    created_at
    updated_at
    settings
  )a

  @get_path_schema [
    service: [type: {:or, [:string, :integer]}, required: true]
  ]

  @domain_service_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    service: [type: {:or, [:string, :integer]}, required: true]
  ]

  @applied_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @list_applied_schema [
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of applied services per page"]
  ]

  @apply_schema [
    settings: [type: :any]
  ]

  @doc """
  Retrieves a global one-click service definition by sid or ID.

  The returned service includes typed timestamps and typed setting definitions.
  Nullable setup text, default subdomain, setting append text, and setting
  examples remain `nil`.
  """
  @spec get(Req.Request.t(), binary() | integer()) :: {:ok, t()} | {:error, term()}
  def get(req, service) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([service: service], @get_path_schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/services/:service",
          path_params_style: :colon,
          path_params: [service: service]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, service} -> {:ok, service}
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
  Lists one page of one-click services applied to a domain.

  Supports `:page` and `:per_page`. Omitted options remain omitted so DNSimple
  applies its server defaults. The returned pagination metadata retains its
  string keys.

  ## Example

      ReqDnsimple.Service.list_page_applied(
        req,
        1010,
        "example.test",
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.Service{}], %{"current_page" => 2}}}
  """
  @spec list_page_applied(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page_applied(req, account_id, domain, opts \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @applied_path_schema
           ),
         {:ok, validated_opts} <-
           ReqDnsimple.validate_options(opts, @list_applied_schema) do
      case request_applied_services(req, account_id, domain, validated_opts) do
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => data, "pagination" => pagination}
         } = response} ->
          case decode_page(data, pagination) do
            {:ok, result} -> {:ok, result}
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
  Lists one page of one-click services applied to a domain.

  This convenience alias delegates to `list_page_applied/4` and never
  enumerates additional pages implicitly.
  """
  @spec list_applied(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_applied(req, account_id, domain, opts \\ []),
    do: list_page_applied(req, account_id, domain, opts)

  @doc """
  Enumerates every page of one-click services applied to a domain.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. `:per_page` is retained for every request.
  """
  @spec list_all_applied(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) :: {:ok, [t()]} | {:error, term()}
  def list_all_applied(req, account_id, domain, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page_applied(req, account_id, domain, &1))
  end

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
             @domain_service_path_schema
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

  @doc """
  Unapplies one selected service from a domain.

  This sends exactly one bodyless request and returns `:ok` only for HTTP 204.
  It does not fetch the service or delete records individually.
  """
  @spec unapply(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          binary() | integer()
        ) :: :ok | {:error, term()}
  def unapply(req, account_id, domain, service) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, service: service],
             @domain_service_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/services/:service",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain, service: service],
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

  defp decode(%{
         "id" => id,
         "name" => name,
         "sid" => sid,
         "description" => description,
         "setup_description" => setup_description,
         "requires_setup" => requires_setup,
         "default_subdomain" => default_subdomain,
         "created_at" => created_at,
         "updated_at" => updated_at,
         "settings" => settings
       })
       when is_integer(id) and is_binary(name) and is_binary(sid) and is_binary(description) and
              (is_binary(setup_description) or is_nil(setup_description)) and
              is_boolean(requires_setup) and
              (is_binary(default_subdomain) or is_nil(default_subdomain)) and
              is_binary(created_at) and is_binary(updated_at) and is_list(settings) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at),
         {:ok, settings} <- decode_settings(settings) do
      {:ok,
       %__MODULE__{
         id: id,
         name: name,
         sid: sid,
         description: description,
         setup_description: setup_description,
         requires_setup: requires_setup,
         default_subdomain: default_subdomain,
         created_at: created_at,
         updated_at: updated_at,
         settings: settings
       }}
    else
      _ -> :error
    end
  end

  defp decode(_data), do: :error

  defp decode_settings(settings) do
    Enum.reduce_while(settings, {:ok, []}, fn setting, {:ok, decoded} ->
      case decode_setting(setting) do
        {:ok, setting} -> {:cont, {:ok, [setting | decoded]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      :error -> :error
    end
  end

  defp decode_setting(%{
         "name" => name,
         "label" => label,
         "append" => append,
         "description" => description,
         "example" => example,
         "password" => password
       })
       when is_binary(name) and is_binary(label) and (is_binary(append) or is_nil(append)) and
              is_binary(description) and (is_binary(example) or is_nil(example)) and
              is_boolean(password) do
    {:ok,
     %Setting{
       name: name,
       label: label,
       append: append,
       description: description,
       example: example,
       password: password
     }}
  end

  defp decode_setting(_setting), do: :error

  defp decode_page(data, pagination) when is_list(data) do
    with {:ok, services} <- decode_many(data),
         true <- valid_pagination?(pagination) do
      {:ok, {services, pagination}}
    else
      _error -> :error
    end
  end

  defp decode_page(_data, _pagination), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, services} ->
      case decode(item) do
        {:ok, service} -> {:cont, {:ok, [service | services]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, services} -> {:ok, Enum.reverse(services)}
      :error -> :error
    end
  end

  defp valid_pagination?(%{
         "current_page" => current_page,
         "per_page" => per_page,
         "total_entries" => total_entries,
         "total_pages" => total_pages
       })
       when is_integer(current_page) and current_page >= 0 and is_integer(per_page) and
              per_page > 0 and is_integer(total_entries) and total_entries >= 0 and
              is_integer(total_pages) and total_pages >= 0,
       do: true

  defp valid_pagination?(_pagination), do: false

  defp request_applied_services(req, account_id, domain, opts) do
    req
    |> Req.merge(
      method: :get,
      url: "/:account_id/domains/:domain/services",
      path_params_style: :colon,
      path_params: [account_id: account_id, domain: domain],
      params: Map.new(opts)
    )
    |> Req.request()
  end

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp validate_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @apply_schema),
         :ok <- validate_settings(validated_attrs) do
      {:ok, validated_attrs}
    end
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
