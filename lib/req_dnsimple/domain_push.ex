defmodule ReqDnsimple.DomainPush do
  @moduledoc """
  DNSimple domain-push API functionality.

  ## Example

      ReqDnsimple.DomainPush.list_page(req, 2020, page: 1, per_page: 30)
      #=> {:ok, {[%ReqDnsimple.DomainPush{}], %{"current_page" => 1}}}

      ReqDnsimple.DomainPush.list_all(req, 2020)
      #=> {:ok, [%ReqDnsimple.DomainPush{}]}

      ReqDnsimple.DomainPush.accept(req, 2020, 1, contact_id: 11)
      #=> :ok

      ReqDnsimple.DomainPush.reject(req, 2020, 1)
      #=> :ok
  """

  # https://developer.dnsimple.com/v2/domains/pushes/#listPushes
  # https://developer.dnsimple.com/v2/domains/pushes/#acceptPush
  # https://developer.dnsimple.com/v2/domains/pushes/#rejectPush

  @type t :: %__MODULE__{
          id: integer(),
          domain_id: integer(),
          contact_id: integer() | nil,
          account_id: ReqDnsimple.account_id(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          accepted_at: DateTime.t() | nil
        }

  defstruct ~w(id domain_id contact_id account_id created_at updated_at accepted_at)a

  @list_path_schema [
    account_id: [type: :integer, required: true]
  ]

  @path_schema [
    account_id: [type: :integer, required: true],
    push_id: [type: :integer, required: true]
  ]

  @accept_schema [
    contact_id: [type: :integer, required: true]
  ]

  @list_schema [
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of pushes per page"]
  ]

  @doc """
  Lists one page of pending domain pushes for the target account.

  Supports `:page` and `:per_page`. Pagination metadata retains its string
  keys, and no request body is sent.
  """
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, opts \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @list_path_schema),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/pushes",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          params: Map.new(validated_opts)
        )

      case Req.request(req) do
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
  Lists one page of pending domain pushes for the target account.

  This convenience alias delegates to `list_page/3` and never enumerates
  additional pages.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, account_id, opts \\ []), do: list_page(req, account_id, opts)

  @doc """
  Enumerates every pending domain push for the target account in server order.

  Enumeration begins at page one. An explicit `:page` option is rejected, while
  `:per_page` is retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, account_id, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  @doc """
  Accepts one pending domain push using a contact from the target account.

  This sends exactly one request. Contact creation, domain retrieval, and
  ownership checks remain server-side responsibilities.
  """
  @spec accept(Req.Request.t(), ReqDnsimple.account_id(), integer(), keyword()) ::
          :ok | {:error, term()}
  def accept(req, account_id, push_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, push_id: push_id],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/pushes/:push_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, push_id: push_id],
          json: Map.new(validated_attrs)
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
  Rejects one pending domain push for the target account.

  This sends exactly one request and does not delete the source domain.
  """
  @spec reject(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          :ok | {:error, term()}
  def reject(req, account_id, push_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, push_id: push_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/pushes/:push_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, push_id: push_id]
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
         "domain_id" => domain_id,
         "contact_id" => contact_id,
         "account_id" => account_id,
         "created_at" => created_at,
         "updated_at" => updated_at,
         "accepted_at" => accepted_at
       })
       when is_integer(id) and is_integer(domain_id) and
              (is_integer(contact_id) or is_nil(contact_id)) and is_integer(account_id) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at),
         {:ok, accepted_at} <- parse_optional_datetime(accepted_at) do
      {:ok,
       %__MODULE__{
         id: id,
         domain_id: domain_id,
         contact_id: contact_id,
         account_id: account_id,
         created_at: created_at,
         updated_at: updated_at,
         accepted_at: accepted_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp decode_page(data, pagination) when is_list(data) do
    with {:ok, pushes} <- decode_many(data),
         true <- valid_pagination?(pagination) do
      {:ok, {pushes, pagination}}
    else
      _error -> :error
    end
  end

  defp decode_page(_data, _pagination), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, pushes} ->
      case decode(item) do
        {:ok, push} -> {:cont, {:ok, [push | pushes]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, pushes} -> {:ok, Enum.reverse(pushes)}
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

  defp parse_optional_datetime(nil), do: {:ok, nil}
  defp parse_optional_datetime(value), do: parse_datetime(value)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp validate_attrs(attrs) do
    ReqDnsimple.validate_options(attrs, @accept_schema)
  end
end
