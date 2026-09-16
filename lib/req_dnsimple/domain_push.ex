defmodule ReqDnsimple.DomainPush do
  @moduledoc """
  DNSimple domain-push API functionality.

  Successful HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}`.
  Failures return `{:error, %ReqDnsimple.Error{}}`, with metadata when an
  HTTP response was received.
  Bodyless HTTP 204 responses use `nil` data.

  Page pagination is nested under `metadata.pagination`. `list_all` retains
  ordered page metadata in `metadata.pages` and the latest rate-limit budget.
  Missing or malformed metadata does not invalidate resource data; diagnostics
  are in `metadata.parse_errors`. Enumeration requires usable pagination.

  ## Example

      ReqDnsimple.DomainPush.initiate(
        req,
        1010,
        "example.test",
        new_account_identifier: "00000000-0000-7000-8000-000000000002"
      )
      #=> {:ok, {%ReqDnsimple.DomainPush{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.DomainPush.list_page(req, 2020, page: 1, per_page: 30)
      #=> {:ok, {[%ReqDnsimple.DomainPush{}], %ReqDnsimple.Metadata{pagination: %{"current_page" => 1}}}}

      ReqDnsimple.DomainPush.list_all(req, 2020)
      #=> {:ok, {[%ReqDnsimple.DomainPush{}], %ReqDnsimple.Metadata{}}}

      ReqDnsimple.DomainPush.accept(req, 2020, 1, contact_id: 11)
      #=> {:ok, {nil, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.DomainPush.reject(req, 2020, 1)
      #=> {:ok, {nil, %ReqDnsimple.Metadata{}}}
  """

  # https://developer.dnsimple.com/v2/domains/pushes/#initiateDomainPush
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

  @initiate_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @path_schema [
    account_id: [type: :integer, required: true],
    push_id: [type: :integer, required: true]
  ]

  @initiate_schema [
    new_account_identifier: [type: :string],
    new_account_email: [type: :string]
  ]

  @accept_schema [
    contact_id: [type: :integer, required: true]
  ]

  @list_schema [
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of pushes per page"]
  ]

  @doc """
  Uses the client's configured account. See `initiate/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec initiate(
          Req.Request.t(),
          String.t() | integer(),
          keyword()
        ) :: ReqDnsimple.Response.result(t())
  def initiate(req, domain, attrs) do
    ReqDnsimple.Client.with_account(req, &initiate(req, &1, domain, attrs))
  end

  @doc """
  Initiates a domain push from the source account to another account.

  Exactly one of `:new_account_identifier` or the deprecated
  `:new_account_email` must be provided. This sends one request and returns the
  pending push without looking up the target account, selecting a contact, or
  accepting the push.
  """
  @spec initiate(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          String.t() | integer(),
          keyword()
        ) :: ReqDnsimple.Response.result(t())
  def initiate(req, account_id, domain, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @initiate_path_schema
           ),
         {:ok, validated_attrs} <- validate_initiate_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/pushes",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, push} -> ReqDnsimple.Response.ok(push, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list_page/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_page(Req.Request.t()) :: ReqDnsimple.Response.result([t()])
  def list_page(req) do
    list_page(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result([t()])
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id()) :: ReqDnsimple.Response.result([t()])
  def list_page(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_page(req, account_id, [])
  end

  def list_page(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, opts))
  end

  @doc """
  Lists one page of pending domain pushes for the target account.

  Supports `:page` and `:per_page`. Pagination metadata retains its string
  keys, and no request body is sent.
  """
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id, opts) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @list_path_schema),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      req =
        ReqDnsimple.Helper.merge(req,
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
           body: %{"data" => data}
         } = response}
        when is_list(data) ->
          case decode_many(data) do
            {:ok, result} -> ReqDnsimple.Response.ok(result, response)
            :error -> ReqDnsimple.response_error(response)
          end

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list(Req.Request.t()) :: ReqDnsimple.Response.result([t()])
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
  @spec list(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result([t()])
  @spec list(Req.Request.t(), ReqDnsimple.account_id()) :: ReqDnsimple.Response.result([t()])
  def list(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list(req, account_id, [])
  end

  def list(req, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, opts))
  end

  @doc """
  Lists one page of pending domain pushes for the target account.

  This convenience alias delegates to `list_page/3` and never enumerates
  additional pages.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, opts), do: list_page(req, account_id, opts)

  @doc """
  Uses the client's configured account with default options.
  See `list_all/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_all(Req.Request.t()) :: ReqDnsimple.Response.result([t()])
  def list_all(req) do
    list_all(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/3` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), keyword()) :: ReqDnsimple.Response.result([t()])
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id()) :: ReqDnsimple.Response.result([t()])
  def list_all(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_all(req, account_id, [])
  end

  def list_all(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, opts))
  end

  @doc """
  Enumerates every pending domain push for the target account in server order.

  Enumeration begins at page one. An explicit `:page` option is rejected, while
  `:per_page` is retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, account_id, opts) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  @doc """
  Uses the client's configured account. See `accept/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec accept(Req.Request.t(), integer(), keyword()) :: ReqDnsimple.Response.result(nil)
  def accept(req, push_id, attrs) do
    ReqDnsimple.Client.with_account(req, &accept(req, &1, push_id, attrs))
  end

  @doc """
  Accepts one pending domain push using a contact from the target account.

  This sends exactly one request. Contact creation, domain retrieval, and
  ownership checks remain server-side responsibilities.
  """
  @spec accept(Req.Request.t(), ReqDnsimple.account_id(), integer(), keyword()) ::
          ReqDnsimple.Response.result(nil)
  def accept(req, account_id, push_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, push_id: push_id],
             @path_schema
           ),
         {:ok, validated_attrs} <- validate_accept_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/pushes/:push_id",
          path_params_style: :colon,
          path_params: [account_id: account_id, push_id: push_id],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 204} = response} ->
          ReqDnsimple.Response.ok(nil, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account. See `reject/3` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec reject(Req.Request.t(), integer()) :: ReqDnsimple.Response.result(nil)
  def reject(req, push_id) do
    ReqDnsimple.Client.with_account(req, &reject(req, &1, push_id))
  end

  @doc """
  Rejects one pending domain push for the target account.

  This sends exactly one request and does not delete the source domain.
  """
  @spec reject(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          ReqDnsimple.Response.result(nil)
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
        {:ok, %Req.Response{status: 204} = response} ->
          ReqDnsimple.Response.ok(nil, response)

        {:ok, response} ->
          ReqDnsimple.response_error(response)

        {:error, error} ->
          ReqDnsimple.Response.error(error)
      end
    end
    |> ReqDnsimple.Response.normalize_error()
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

  defp parse_optional_datetime(nil), do: {:ok, nil}
  defp parse_optional_datetime(value), do: parse_datetime(value)

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp validate_initiate_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @initiate_schema),
         :ok <- validate_push_target(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_push_target(attrs) do
    case {Keyword.has_key?(attrs, :new_account_identifier),
          Keyword.has_key?(attrs, :new_account_email)} do
      {true, false} ->
        :ok

      {false, true} ->
        :ok

      _other ->
        {:error,
         %NimbleOptions.ValidationError{
           message: "expected exactly one of :new_account_identifier or :new_account_email",
           value: attrs
         }}
    end
  end

  defp validate_accept_attrs(attrs) do
    ReqDnsimple.validate_options(attrs, @accept_schema)
  end
end
