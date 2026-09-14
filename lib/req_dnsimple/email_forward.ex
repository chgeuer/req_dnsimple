defmodule ReqDnsimple.EmailForward do
  @moduledoc """
  Operations for domain email forwards.

  Create one email forward:

      {:ok, email_forward} =
        ReqDnsimple.EmailForward.create(
          client,
          1010,
          "example.test",
          alias_name: "support",
          destination_email: "recipient@example.test"
        )

  Retrieve one email forward:

      {:ok, email_forward} =
        ReqDnsimple.EmailForward.get(
          client,
          1010,
          "example.test",
          1
        )

  List one page or explicitly enumerate every email forward:

      {:ok, {email_forwards, pagination}} =
        ReqDnsimple.EmailForward.list_page(
          client,
          1010,
          "example.test",
          sort: [id: :asc, alias_email: :desc],
          page: 2,
          per_page: 30
        )

      {:ok, all_email_forwards} =
        ReqDnsimple.EmailForward.list_all(
          client,
          1010,
          "example.test",
          sort: [destination_email: :asc]
        )

  Delete one email forward:

      :ok =
        ReqDnsimple.EmailForward.delete(
          client,
          1010,
          "example.test",
          1
        )

  Deletion removes only the selected email forward. It does not send mail or
  modify the domain's MX records.
  """

  @type t :: %__MODULE__{
          id: integer(),
          domain_id: integer(),
          alias_email: binary(),
          destination_email: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          active: boolean()
        }

  defstruct ~w(id domain_id alias_email destination_email created_at updated_at active)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    email_forward_id: [type: :integer, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true]
  ]

  @create_schema [
    alias_name: [type: :string, required: true],
    destination_email: [type: :string, required: true]
  ]

  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :alias_email, :destination_email]]},
      doc: "Sort by id, alias_email, or destination_email. Format: [id: :asc, alias_email: :desc]"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of email forwards per page"]
  ]

  @doc """
  Uses the client's configured account. See `create/4` for
  operation options and return values. Returns `{:error, :missing_account_id}`
  without making a request when the client is unscoped.
  """
  @spec create(Req.Request.t(), binary() | integer(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def create(req, domain, attrs) do
    ReqDnsimple.Client.with_account(req, &create(req, &1, domain, attrs))
  end

  @doc """
  Creates an email forward for a domain.

  `alias_name` is sent unchanged as the receiving local part; DNSimple appends
  the domain. The operation sends one request and does not provision DNS
  records or send a test email.

  ## Example

      ReqDnsimple.EmailForward.create(
        req,
        1010,
        "example.test",
        alias_name: "support",
        destination_email: "recipient@example.test"
      )
      #=> {:ok, %ReqDnsimple.EmailForward{}}
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def create(req, account_id, domain, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @create_path_schema
           ),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/email_forwards",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, email_forward} -> {:ok, email_forward}
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
  Uses the client's configured account with default options.
  See `list_page/4` for operation options and return values.
  Returns `{:error, :missing_account_id}` without making a request when the client is unscoped.
  """
  @spec list_page(
          Req.Request.t(),
          binary() | integer()
        ) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, domain) do
    list_page(req, domain, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/4` for operation options and return values.
  Returns `{:error, :missing_account_id}` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(
          Req.Request.t(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  @spec list_page(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, domain)
      when is_integer(domain) or is_binary(domain) do
    list_page(req, account_id, domain, [])
  end

  def list_page(req, domain, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, domain, opts))
  end

  @doc """
  Lists one page of email forwards for a domain.

  Supports ordered `:sort` terms for `:id`, `:alias_email`, and
  `:destination_email`, plus `:page` and `:per_page`. The returned pagination
  metadata retains its string keys.

  ## Example

      ReqDnsimple.EmailForward.list_page(
        req,
        1010,
        "example.test",
        sort: [id: :asc, alias_email: :desc],
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.EmailForward{}], %{"current_page" => 2}}}
  """
  @spec list_page(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, domain, opts) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain],
             @create_path_schema
           ),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      case request_list(req, account_id, domain, validated_opts) do
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
  Uses the client's configured account with default options.
  See `list/4` for operation options and return values.
  Returns `{:error, :missing_account_id}` without making a request when the client is unscoped.
  """
  @spec list(Req.Request.t(), binary() | integer()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, domain) do
    list(req, domain, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/4` for operation options and return values.
  Returns `{:error, :missing_account_id}` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list(Req.Request.t(), binary() | integer(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, account_id, domain)
      when is_integer(domain) or is_binary(domain) do
    list(req, account_id, domain, [])
  end

  def list(req, domain, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, domain, opts))
  end

  @doc """
  Lists one page of email forwards for a domain.

  This is a convenience alias for `list_page/4`; it never enumerates additional
  pages implicitly.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, account_id, domain, opts), do: list_page(req, account_id, domain, opts)

  @doc """
  Uses the client's configured account with default options.
  See `list_all/4` for operation options and return values.
  Returns `{:error, :missing_account_id}` without making a request when the client is unscoped.
  """
  @spec list_all(Req.Request.t(), binary() | integer()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, domain) do
    list_all(req, domain, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/4` for operation options and return values.
  Returns `{:error, :missing_account_id}` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), binary() | integer(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, account_id, domain)
      when is_integer(domain) or is_binary(domain) do
    list_all(req, account_id, domain, [])
  end

  def list_all(req, domain, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, domain, opts))
  end

  @doc """
  Enumerates every page of email forwards in server order.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. Sorting and `:per_page` are retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, account_id, domain, opts) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, domain, &1))
  end

  @doc """
  Uses the client's configured account. See `get/4` for
  operation options and return values. Returns `{:error, :missing_account_id}`
  without making a request when the client is unscoped.
  """
  @spec get(Req.Request.t(), binary() | integer(), integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, domain, email_forward_id) do
    ReqDnsimple.Client.with_account(req, &get(req, &1, domain, email_forward_id))
  end

  @doc """
  Retrieves one email forward from a domain.

  The returned struct keeps the full alias email distinct from the local-part
  `alias_name` accepted by email-forward creation.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, domain, email_forward_id) do
    with {:ok, _validated_params} <-
           validate_path(account_id, domain, email_forward_id) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/domains/:domain/email_forwards/:email_forward_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            email_forward_id: email_forward_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, email_forward} -> {:ok, email_forward}
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
  Uses the client's configured account. See `delete/4` for
  operation options and return values. Returns `{:error, :missing_account_id}`
  without making a request when the client is unscoped.
  """
  @spec delete(Req.Request.t(), binary() | integer(), integer()) ::
          :ok | {:error, term()}
  def delete(req, domain, email_forward_id) do
    ReqDnsimple.Client.with_account(req, &delete(req, &1, domain, email_forward_id))
  end

  @doc """
  Deletes one email forward from a domain.

  Returns `:ok` for the API's empty HTTP 204 response. Deletion refusals,
  missing forwards, other HTTP responses, and transport failures are returned
  as explicit error tuples.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, domain, email_forward_id) do
    with {:ok, _validated_params} <-
           validate_path(account_id, domain, email_forward_id) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/domains/:domain/email_forwards/:email_forward_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            domain: domain,
            email_forward_id: email_forward_id
          ]
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

  defp validate_path(account_id, domain, email_forward_id) do
    NimbleOptions.validate(
      [
        account_id: account_id,
        domain: domain,
        email_forward_id: email_forward_id
      ],
      @path_schema
    )
  end

  defp decode(%{
         "id" => id,
         "domain_id" => domain_id,
         "alias_email" => alias_email,
         "destination_email" => destination_email,
         "created_at" => created_at,
         "updated_at" => updated_at,
         "active" => active
       })
       when is_integer(id) and is_integer(domain_id) and is_binary(alias_email) and
              is_binary(destination_email) and is_boolean(active) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         domain_id: domain_id,
         alias_email: alias_email,
         destination_email: destination_email,
         created_at: created_at,
         updated_at: updated_at,
         active: active
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp decode_page(data, pagination) when is_list(data) do
    with {:ok, email_forwards} <- decode_many(data),
         true <- valid_pagination?(pagination) do
      {:ok, {email_forwards, pagination}}
    else
      _error -> :error
    end
  end

  defp decode_page(_data, _pagination), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, email_forwards} ->
      case decode(item) do
        {:ok, email_forward} ->
          {:cont, {:ok, [email_forward | email_forwards]}}

        :error ->
          {:halt, :error}
      end
    end)
    |> case do
      {:ok, email_forwards} -> {:ok, Enum.reverse(email_forwards)}
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

  defp request_list(req, account_id, domain, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> Req.merge(
      method: :get,
      url: "/:account_id/domains/:domain/email_forwards",
      path_params_style: :colon,
      path_params: [account_id: account_id, domain: domain],
      params: params
    )
    |> Req.request()
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error
end
