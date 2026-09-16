defmodule ReqDnsimple.RegistrantChange do
  @moduledoc """
  Checks requirements, creates, lists, retrieves, and cancels registrar
  contact-change requests.

  HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}`; HTTP 204
  responses use `nil` data. List data contains only the resources, while the
  original string-key pagination map is nested in `metadata.pagination`.
  Missing or malformed metadata never discards valid resource data; parse
  failures are recorded in `metadata.parse_errors`.

  Failures return `{:error, %ReqDnsimple.Error{}}`, with HTTP response metadata
  when available and `nil` metadata for direct local or transport failures.
  `list_all` retains metadata from completed pages when enumeration fails.

  ## Example

      ReqDnsimple.RegistrantChange.check(req, 1010,
        domain_id: "example.test",
        contact_id: "11"
      )
      #=> {:ok, {%ReqDnsimple.RegistrantChange.CheckResult{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.RegistrantChange.create(
        req,
        1010,
        domain_id: "example.test",
        contact_id: "11",
        extended_attributes: %{
          "x-fi-registrant-idnumber" => "fake-offline-id"
        }
      )
      #=> {:ok, {%ReqDnsimple.RegistrantChange{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.RegistrantChange.get(req, 1010, 1)
      #=> {:ok, {%ReqDnsimple.RegistrantChange{}, %ReqDnsimple.Metadata{}}}

      ReqDnsimple.RegistrantChange.list_page(req, 1010,
        sort: [id: :asc],
        state: "completed",
        domain_id: "100",
        contact_id: "11",
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.RegistrantChange{}], %ReqDnsimple.Metadata{pagination: %{"current_page" => 2}}}}

      ReqDnsimple.RegistrantChange.list_all(req, 1010, state: "pending")
      #=> {:ok, {[%ReqDnsimple.RegistrantChange{}], %ReqDnsimple.Metadata{}}}

      ReqDnsimple.RegistrantChange.cancel(req, 1010, 1)
      #=> {:ok, {%ReqDnsimple.RegistrantChange{state: "cancelling"}, %ReqDnsimple.Metadata{}}}
  """

  @type state :: String.t()

  @type t :: %__MODULE__{
          id: integer(),
          account_id: integer(),
          contact_id: integer(),
          domain_id: integer(),
          state: state(),
          extended_attributes: %{String.t() => String.t()},
          registry_owner_change: boolean(),
          irt_lock_lifted_by: Date.t() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :account_id,
    :contact_id,
    :domain_id,
    :state,
    :extended_attributes,
    :registry_owner_change,
    :irt_lock_lifted_by,
    :created_at,
    :updated_at
  ]

  defmodule CheckResult do
    @moduledoc """
    Registrant-change requirements returned before starting a contact change.

    Extended attribute definitions are preserved as a list of maps because
    their contents depend on the domain's registry.
    """

    @type t :: %__MODULE__{
            domain_id: integer(),
            contact_id: integer(),
            extended_attributes: [map()],
            registry_owner_change: boolean()
          }

    defstruct [:domain_id, :contact_id, :extended_attributes, :registry_owner_change]
  end

  @path_schema [
    account_id: [type: :integer, required: true],
    registrant_change_id: [type: :integer, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true]
  ]

  @create_schema [
    domain_id: [type: {:or, [:string, :integer]}, required: true],
    contact_id: [type: {:or, [:string, :integer]}, required: true],
    extended_attributes: [type: :any]
  ]

  @check_schema [
    domain_id: [type: {:or, [:string, :integer]}, required: true],
    contact_id: [type: {:or, [:string, :integer]}, required: true]
  ]

  @states ~w(new pending cancelling cancelled completed)

  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id]]},
      doc: "Sort by id. Format: [id: :asc]"
    ],
    state: [type: {:in, @states}, doc: "Filter by registrant-change state"],
    domain_id: [type: :string, doc: "Filter by domain ID"],
    contact_id: [type: :string, doc: "Filter by contact ID"],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of registrant changes per page"]
  ]

  @doc """
  Checks registrant-change requirements using the client's configured account.

  See `check/3` for the required `:domain_id` and `:contact_id` attributes and
  return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` before authentication
  or HTTP when the client has no configured account.
  """
  @spec check(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result(CheckResult.t())
  def check(req, attrs) do
    ReqDnsimple.Client.with_account(req, &check(req, &1, attrs))
  end

  @doc """
  Checks the requirements for changing a domain's registrant contact.

  The required `:domain_id` accepts a domain name or integer ID, and the required
  `:contact_id` accepts a string or integer ID. Both are sent in the root JSON
  object. This sends exactly one POST request with retries disabled, without
  creating a registrant change or performing any follow-up mutation.

  Returns `{:ok, {result, %ReqDnsimple.Metadata{}}}` with a typed `CheckResult` on HTTP 200, preserving the
  registry's extended-attribute definitions and owner-change flag. Validation
  failures, malformed success bodies, other HTTP responses, and transport
  failures return `{:error, %ReqDnsimple.Error{reason: reason}}`.

  ## Example

      ReqDnsimple.RegistrantChange.check(req, 1010,
        domain_id: "example.com",
        contact_id: "101"
      )
      #=> {:ok, {%ReqDnsimple.RegistrantChange.CheckResult{}, %ReqDnsimple.Metadata{}}}
  """
  @spec check(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result(CheckResult.t())
  def check(req, account_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @check_schema) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/registrant_changes/check",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode_check_result(data) do
            {:ok, result} -> ReqDnsimple.Response.ok(result, response)
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
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec create(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def create(req, attrs) do
    ReqDnsimple.Client.with_account(req, &create(req, &1, attrs))
  end

  @doc """
  Starts a registrar contact-change request.

  `domain_id` and `contact_id` accept their integer IDs or string forms; a
  domain name is also accepted for `domain_id`. Optional `extended_attributes`
  must be a map of registry-defined string keys and string values. An omitted
  map remains omitted, while an explicit empty map is sent unchanged.

  The function returns both immediately completed (`201`) and pending (`202`)
  requests without polling. It performs no requirements check or follow-up
  mutation.

  ## Example

      ReqDnsimple.RegistrantChange.create(
        req,
        1010,
        domain_id: "example.test",
        contact_id: "11",
        extended_attributes: %{
          "x-fi-registrant-idnumber" => "fake-offline-id"
        }
      )
      #=> {:ok, {%ReqDnsimple.RegistrantChange{}, %ReqDnsimple.Metadata{}}}
  """
  @spec create(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result(t())
  def create(req, account_id, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_attrs} <- validate_create_attrs(attrs) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/registrar/registrant_changes",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs)
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: %{"data" => data}} = response}
        when status in [201, 202] ->
          case decode(data) do
            {:ok, registrant_change} -> ReqDnsimple.Response.ok(registrant_change, response)
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
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec get(Req.Request.t(), integer()) ::
          ReqDnsimple.Response.result(t())
  def get(req, registrant_change_id) do
    ReqDnsimple.Client.with_account(req, &get(req, &1, registrant_change_id))
  end

  @doc """
  Retrieves a registrar contact-change request.

  Returns its current state and registry requirements in a typed struct. The
  registry lock-lift date is `nil` until supplied by DNSimple. This function
  sends one bodyless request and performs no requirements check or mutation.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          ReqDnsimple.Response.result(t())
  def get(req, account_id, registrant_change_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               registrant_change_id: registrant_change_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/registrar/registrant_changes/:registrant_change_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            registrant_change_id: registrant_change_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, registrant_change} -> ReqDnsimple.Response.ok(registrant_change, response)
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
  Uses the client's configured account with default options.
  See `list_page/3` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.
  """
  @spec list_page(Req.Request.t()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req) do
    list_page(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/3` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_page(req, account_id, [])
  end

  def list_page(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, opts))
  end

  @doc """
  Lists one page of registrar contact-change requests.

  Supports `:state`, string `:domain_id` and `:contact_id` filters, `:page`,
  `:per_page`, and ordered `:id` sorting. Omitted filters remain omitted so
  DNSimple retains its default open-state filter.

  ## Example

      ReqDnsimple.RegistrantChange.list_page(
        req,
        1010,
        sort: [id: :asc],
        state: "completed",
        domain_id: "100",
        contact_id: "11",
        page: 2,
        per_page: 30
      )
      #=> {:ok, {[%ReqDnsimple.RegistrantChange{}], %ReqDnsimple.Metadata{pagination: %{"current_page" => 2}}}}
  """
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id, opts) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @create_path_schema),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      req =
        ReqDnsimple.Helper.merge(req,
          method: :get,
          url: "/:account_id/registrar/registrant_changes",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          params: validated_opts |> ReqDnsimple.convert_sort_to_string() |> Map.new()
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
          {:error, error}
      end
    end
    |> ReqDnsimple.Response.normalize_error()
  end

  @doc """
  Uses the client's configured account with default options.
  See `list/3` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.
  """
  @spec list(Req.Request.t()) ::
          ReqDnsimple.Response.result([t()])
  def list(req) do
    list(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/3` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.

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
  Lists one page of registrar contact-change requests.

  This convenience alias delegates to `list_page/3` and never enumerates
  additional pages.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, opts), do: list_page(req, account_id, opts)

  @doc """
  Uses the client's configured account with default options.
  See `list_all/3` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.
  """
  @spec list_all(Req.Request.t()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req) do
    list_all(req, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/3` for operation options and return values.
  Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}` without making a request when the client is unscoped.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, account_id)
      when is_integer(account_id) or is_binary(account_id) do
    list_all(req, account_id, [])
  end

  def list_all(req, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, opts))
  end

  @doc """
  Enumerates every matching registrar contact-change request in server order.

  Enumeration begins at page one. An explicit `:page` option is rejected;
  filters, sorting, and `:per_page` are retained for every request.
  Returns all resources with aggregate metadata whose `pages` retain each
  response's metadata. Aggregate status, pagination, request ID, and ETag are
  `nil`; rate-limit and Retry-After fields reflect the latest page. Enumeration
  errors retain the metadata collected before the failure.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, account_id, opts) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  @doc """
  Uses the client's configured account. See `cancel/3` for
  operation options and return values. Returns `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request when the client is unscoped.
  """
  @spec cancel(Req.Request.t(), integer()) ::
          ReqDnsimple.Response.result(t() | nil)
  def cancel(req, registrant_change_id) do
    ReqDnsimple.Client.with_account(req, &cancel(req, &1, registrant_change_id))
  end

  @doc """
  Cancels a registrar contact-change request.

  Returns `{:ok, {%ReqDnsimple.RegistrantChange{}, %ReqDnsimple.Metadata{}}}` for an asynchronous
  cancellation (`202`) and `{:ok, {nil, %ReqDnsimple.Metadata{status: 204}}}` when cancellation completes immediately
  (`204`). It sends one bodyless request and does not poll for completion.
  """
  @spec cancel(Req.Request.t(), ReqDnsimple.account_id(), integer()) ::
          ReqDnsimple.Response.result(t() | nil)
  def cancel(req, account_id, registrant_change_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [
               account_id: account_id,
               registrant_change_id: registrant_change_id
             ],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/registrar/registrant_changes/:registrant_change_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            registrant_change_id: registrant_change_id
          ],
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 202, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, registrant_change} -> ReqDnsimple.Response.ok(registrant_change, response)
            :error -> ReqDnsimple.response_error(response)
          end

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

  defp decode_check_result(%{
         "domain_id" => domain_id,
         "contact_id" => contact_id,
         "extended_attributes" => extended_attributes,
         "registry_owner_change" => registry_owner_change
       })
       when is_integer(domain_id) and is_integer(contact_id) and
              is_list(extended_attributes) and is_boolean(registry_owner_change) do
    if Enum.all?(extended_attributes, &(is_map(&1) and not is_struct(&1))) do
      {:ok,
       %CheckResult{
         domain_id: domain_id,
         contact_id: contact_id,
         extended_attributes: extended_attributes,
         registry_owner_change: registry_owner_change
       }}
    else
      :error
    end
  end

  defp decode_check_result(_data), do: :error

  defp decode(%{
         "id" => id,
         "account_id" => account_id,
         "contact_id" => contact_id,
         "domain_id" => domain_id,
         "state" => state,
         "extended_attributes" => extended_attributes,
         "registry_owner_change" => registry_owner_change,
         "irt_lock_lifted_by" => irt_lock_lifted_by,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(account_id) and is_integer(contact_id) and
              is_integer(domain_id) and state in @states and is_map(extended_attributes) and
              is_boolean(registry_owner_change) do
    with true <-
           Enum.all?(extended_attributes, fn {key, value} ->
             is_binary(key) and is_binary(value)
           end),
         {:ok, irt_lock_lifted_by} <- parse_optional_date(irt_lock_lifted_by),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         contact_id: contact_id,
         domain_id: domain_id,
         state: state,
         extended_attributes: extended_attributes,
         registry_owner_change: registry_owner_change,
         irt_lock_lifted_by: irt_lock_lifted_by,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _invalid -> :error
    end
  end

  defp decode(_data), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, registrant_changes} ->
      case decode(item) do
        {:ok, registrant_change} -> {:cont, {:ok, [registrant_change | registrant_changes]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, registrant_changes} -> {:ok, Enum.reverse(registrant_changes)}
      :error -> :error
    end
  end

  defp parse_optional_date(nil), do: {:ok, nil}

  defp parse_optional_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parse_optional_date(_value), do: :error

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end

  defp parse_datetime(_value), do: :error

  defp validate_create_attrs(attrs) do
    with {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema),
         :ok <- validate_extended_attributes(validated_attrs) do
      {:ok, validated_attrs}
    end
  end

  defp validate_extended_attributes(attrs) do
    case Keyword.fetch(attrs, :extended_attributes) do
      :error -> :ok
      {:ok, extended_attributes} -> validate_extended_attributes_map(extended_attributes)
    end
  end

  defp validate_extended_attributes_map(map) when is_map(map) and not is_struct(map) do
    if Enum.all?(map, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      :ok
    else
      {:error,
       %NimbleOptions.ValidationError{
         message: "expected :extended_attributes to have string keys and values",
         key: :extended_attributes,
         value: map
       }}
    end
  end

  defp validate_extended_attributes_map(value) do
    {:error,
     %NimbleOptions.ValidationError{
       message: "expected :extended_attributes to be a map with string keys and values",
       key: :extended_attributes,
       value: value
     }}
  end
end
