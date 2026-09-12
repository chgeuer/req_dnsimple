defmodule ReqDnsimple.Domain do
  @moduledoc """
  DNSimple Domain API functionality.

  ## Example

      ReqDnsimple.Domain.create(req, 1010, name: "example.test")
      #=> {:ok, %ReqDnsimple.Domain{}}

      ReqDnsimple.Domain.get(req, 1010, "example.test")
      #=> {:ok, %ReqDnsimple.Domain{}}

      ReqDnsimple.Domain.list_page(req, 1010,
        name_like: "example",
        sort: [name: :asc],
        page: 1,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.Domain{}], %{"current_page" => 1}}}

      ReqDnsimple.Domain.list_all(req, 1010, registrant_id: 42)
      #=> {:ok, [%ReqDnsimple.Domain{}]}

      ReqDnsimple.Domain.delete(req, 1010, "example.test")
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/domains/#createDomain
  # https://developer.dnsimple.com/v2/domains/#getDomain
  # https://developer.dnsimple.com/v2/domains/#listDomains
  # https://developer.dnsimple.com/v2/domains/#deleteDomain

  @type t :: %__MODULE__{
          id: integer(),
          account_id: ReqDnsimple.account_id(),
          registrant_id: integer() | nil,
          name: binary(),
          unicode_name: binary(),
          state: binary(),
          auto_renew: boolean(),
          private_whois: boolean(),
          expires_at: DateTime.t() | nil,
          trustee: boolean() | nil,
          expires_on: Date.t() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id account_id registrant_id name unicode_name state auto_renew private_whois
               expires_at trustee expires_on created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true]
  ]

  @create_schema [
    name: [type: :string, required: true]
  ]

  @list_schema [
    name_like: [type: :string, doc: "Include domain names containing this substring"],
    registrant_id: [type: :integer, doc: "Include domains with this registrant ID"],
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :name, :expiration]]},
      doc: "Sort by id, name, or expiration"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of domains per page"]
  ]

  @doc """
  Adds a hosted domain to an account.

  The required `name` is sent in one request. DNSimple may charge for the DNS
  service subscription. This operation does not register or purchase the
  domain, change delegation, verify ownership, or create a zone separately.

  ## Example

      ReqDnsimple.Domain.create(req, 1010, name: "example.test")
      #=> {:ok, %ReqDnsimple.Domain{}}
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def create(req, account_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, domain} -> {:ok, domain}
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
  Lists one page of domains accessible to an account.

  Supports `:name_like` and `:registrant_id` filters, ordered `:sort` terms for
  `:id`, `:name`, and `:expiration`, plus `:page` and `:per_page`. Pagination
  metadata retains its string keys.
  """
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, opts \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      case request_list(req, account_id, validated_opts) do
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
  Lists one page of domains accessible to an account.

  This is a convenience alias for `list_page/3`; it never enumerates additional
  pages implicitly.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, account_id, opts \\ []), do: list_page(req, account_id, opts)

  @doc """
  Enumerates every domain accessible to an account in server order.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. Filters, sorting, and `:per_page` are retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, account_id, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  @doc """
  Retrieves one hosted or registered domain by name or ID.

  Registration, privacy, renewal, and expiry fields are returned without
  inferring state from nullable expiry values. Optional `trustee` and
  `expires_on` fields are `nil` when omitted by older API responses.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate([account_id: account_id, domain: domain], @path_schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, domain} -> {:ok, domain}
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
  Deletes one domain from an account.

  This irreversible account operation does not delete a registration at the
  registry or produce a refund.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain) do
    with {:ok, _validated_params} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain]
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

  defp decode(
         %{
           "id" => id,
           "account_id" => account_id,
           "registrant_id" => registrant_id,
           "name" => name,
           "unicode_name" => unicode_name,
           "state" => state,
           "auto_renew" => auto_renew,
           "private_whois" => private_whois,
           "expires_at" => expires_at,
           "created_at" => created_at,
           "updated_at" => updated_at
         } = data
       )
       when is_integer(id) and is_integer(account_id) and
              (is_integer(registrant_id) or is_nil(registrant_id)) and is_binary(name) and
              is_binary(unicode_name) and state in ["hosted", "registered", "expired"] and
              is_boolean(auto_renew) and is_boolean(private_whois) do
    expires_on = Map.get(data, "expires_on")

    with {:ok, trustee} <- decode_optional_boolean(data, "trustee"),
         {:ok, expires_at} <- parse_optional_datetime(expires_at),
         {:ok, expires_on} <- parse_optional_date(expires_on),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         registrant_id: registrant_id,
         name: name,
         unicode_name: unicode_name,
         state: state,
         auto_renew: auto_renew,
         private_whois: private_whois,
         expires_at: expires_at,
         trustee: trustee,
         expires_on: expires_on,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp decode_page(data, pagination) when is_list(data) do
    with {:ok, domains} <- decode_many(data),
         true <- valid_pagination?(pagination) do
      {:ok, {domains, pagination}}
    else
      _error -> :error
    end
  end

  defp decode_page(_data, _pagination), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, domains} ->
      case decode(item) do
        {:ok, domain} -> {:cont, {:ok, [domain | domains]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, domains} -> {:ok, Enum.reverse(domains)}
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

  defp request_list(req, account_id, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> Req.merge(
      method: :get,
      url: "/:account_id/domains",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end

  defp decode_optional_boolean(data, key) do
    case Map.fetch(data, key) do
      :error -> {:ok, nil}
      {:ok, value} when is_boolean(value) -> {:ok, value}
      {:ok, _value} -> :error
    end
  end

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
    Date.from_iso8601(value)
  end

  defp parse_optional_date(_value), do: :error
end
