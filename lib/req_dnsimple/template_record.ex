defmodule ReqDnsimple.TemplateRecord do
  @moduledoc """
  Operations for records in DNS templates.

  HTTP operations return `{:ok, {data, %ReqDnsimple.Metadata{}}}` or
  `{:error, %ReqDnsimple.Error{}}`. HTTP 204 successes have `nil` data.
  Errors preserve their original reason in `error.reason`. When no response
  has been received, `error.metadata` is `nil`.
  Collection pagination is nested in `metadata.pagination`. Complete
  enumeration retains ordered page metadata in `metadata.pages` and the
  latest rate-limit budget at the top level.

  Known record types accept uppercase, lowercase, or mixed case. The supplied
  spelling is preserved in the request body.

  Create one template record with a flat attribute list:

      {:ok, {record, metadata}} =
        ReqDnsimple.TemplateRecord.create(
          client,
          1010,
          "offline-template",
          name: "",
          type: "MX",
          content: "mail.{{domain}}",
          ttl: 0,
          priority: 0
        )

  Retrieve one typed template record:

      {:ok, {record, metadata}} =
        ReqDnsimple.TemplateRecord.get(
          client,
          1010,
          "offline-template",
          1
        )

  List one page or deliberately enumerate every page:

      {:ok, {records, metadata}} =
        ReqDnsimple.TemplateRecord.list_page(
          client,
          1010,
          "offline-template",
          sort: [id: :asc, name: :desc],
          page: 2,
          per_page: 30
        )

      {:ok, {records, metadata}} =
        ReqDnsimple.TemplateRecord.list_all(
          client,
          1010,
          "offline-template",
          sort: [type: :asc]
        )

  Delete one template record:

      {:ok, {nil, metadata}} =
        ReqDnsimple.TemplateRecord.delete(
          client,
          1010,
          "offline-template",
          1
        )

  Deletion removes only the selected record from the template. It does not
  remove the template or records previously applied to domains.
  """

  @type t :: %__MODULE__{
          id: integer(),
          template_id: integer(),
          name: binary(),
          content: binary(),
          ttl: non_neg_integer(),
          priority: integer() | nil,
          type: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id template_id name content ttl priority type created_at updated_at)a

  @record_types ~w[A AAAA ALIAS CAA CNAME DNSKEY DS HINFO MX NAPTR NS POOL PTR SOA SPF SRV SSHFP TXT URL]
  @numeric_priority ~r/\A[0-9]+\z/

  @path_schema [
    account_id: [type: :integer, required: true],
    template: [type: {:or, [:string, :integer]}, required: true],
    record_id: [type: :integer, required: true]
  ]

  @create_path_schema [
    account_id: [type: :integer, required: true],
    template: [type: {:or, [:string, :integer]}, required: true]
  ]

  @create_schema [
    name: [type: :string, required: true],
    type: [type: :string, required: true],
    content: [type: :string, required: true],
    ttl: [type: :non_neg_integer],
    priority: [type: :integer]
  ]

  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :name, :content, :type]]},
      doc: "Sort by id, name, content, or type"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of template records per page"]
  ]

  @doc """
  Uses the client's configured account. See `create/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec create(
          Req.Request.t(),
          binary() | integer(),
          keyword()
        ) :: ReqDnsimple.Response.result(t())
  def create(req, template, attrs) do
    ReqDnsimple.Client.with_account(req, &create(req, &1, template, attrs))
  end

  @doc """
  Creates one record in a DNS template.

  The template may be a short name or integer ID. Attributes are sent as a
  flat JSON object; `name`, `type`, and `content` are required, while `ttl`
  and `priority` are optional. Empty apex names, literal placeholders, and
  explicit zero values are preserved. Known record types are validated
  case-insensitively without rewriting their spelling. This sends exactly
  one request.
  """
  @spec create(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) :: ReqDnsimple.Response.result(t())
  def create(req, account_id, template, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @create_path_schema
           ),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema),
         :ok <- validate_record_type(validated_attrs[:type]) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/templates/:template/records",
          path_params_style: :colon,
          path_params: [account_id: account_id, template: template],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, record} -> ReqDnsimple.Response.ok(record, response)
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
  See `list_page/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_page(
          Req.Request.t(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, template) do
    list_page(req, template, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_page/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_page(
          Req.Request.t(),
          binary() | integer(),
          keyword()
        ) ::
          ReqDnsimple.Response.result([t()])
  @spec list_page(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer()
        ) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id, template)
      when is_integer(template) or is_binary(template) do
    list_page(req, account_id, template, [])
  end

  def list_page(req, template, opts) do
    ReqDnsimple.Client.with_account(req, &list_page(req, &1, template, opts))
  end

  @doc """
  Lists one page of records in a DNS template.

  The template may be a short name or integer ID. Supports ordered `:sort`
  terms for `:id`, `:name`, `:content`, and `:type`, plus `:page` and
  `:per_page`. Pagination retains its string keys in `metadata.pagination`.
  """
  @spec list_page(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) ::
          ReqDnsimple.Response.result([t()])
  def list_page(req, account_id, template, opts) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @create_path_schema
           ),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema) do
      case request_list(req, account_id, template, validated_opts) do
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => data}
         } = response} ->
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
  See `list/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list(Req.Request.t(), binary() | integer()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, template) do
    list(req, template, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list(Req.Request.t(), binary() | integer(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, template)
      when is_integer(template) or is_binary(template) do
    list(req, account_id, template, [])
  end

  def list(req, template, opts) do
    ReqDnsimple.Client.with_account(req, &list(req, &1, template, opts))
  end

  @doc """
  Lists one page of records in a DNS template.

  This is a convenience alias for `list_page/4`; it never enumerates additional
  pages implicitly.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list(req, account_id, template, opts),
    do: list_page(req, account_id, template, opts)

  @doc """
  Uses the client's configured account with default options.
  See `list_all/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec list_all(Req.Request.t(), binary() | integer()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, template) do
    list_all(req, template, [])
  end

  @doc """
  Uses the client's configured account and the supplied options.
  See `list_all/4` for operation options and return values.
  An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.

  An integer or string final argument selects the legacy explicit-account
  form with default options instead; it overrides the scope for that call only.
  """
  @spec list_all(Req.Request.t(), binary() | integer(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, account_id, template)
      when is_integer(template) or is_binary(template) do
    list_all(req, account_id, template, [])
  end

  def list_all(req, template, opts) do
    ReqDnsimple.Client.with_account(req, &list_all(req, &1, template, opts))
  end

  @doc """
  Enumerates every page of records in a DNS template in server order.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. Sorting and `:per_page` are retained for every request.

  The returned metadata retains all responses in `metadata.pages`, in order,
  and the latest rate-limit budget. Aggregate `status`, `pagination`,
  `request_id`, and `etag` are `nil`. A later failure retains completed page
  metadata in `error.metadata.pages`.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer(), keyword()) ::
          ReqDnsimple.Response.result([t()])
  def list_all(req, account_id, template, opts) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, template, &1))
  end

  @doc """
  Uses the client's configured account. See `get/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec get(
          Req.Request.t(),
          binary() | integer(),
          integer()
        ) :: ReqDnsimple.Response.result(t())
  def get(req, template, record_id) do
    ReqDnsimple.Client.with_account(req, &get(req, &1, template, record_id))
  end

  @doc """
  Retrieves one record from a DNS template.

  The template may be a short name or integer ID. This sends exactly one
  bodyless request and returns a typed record with parsed timestamps.
  Legacy priority strings must contain only ASCII digits; malformed values
  return an error tuple.
  """
  @spec get(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) :: ReqDnsimple.Response.result(t())
  def get(req, account_id, template, record_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template, record_id: record_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/templates/:template/records/:record_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            template: template,
            record_id: record_id
          ]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, record} -> ReqDnsimple.Response.ok(record, response)
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
  Uses the client's configured account. See `delete/4` for
  operation options and return values. An unscoped client returns
  `{:error, %ReqDnsimple.Error{reason: :missing_account_id, metadata: nil}}`
  without making a request.
  """
  @spec delete(
          Req.Request.t(),
          binary() | integer(),
          integer()
        ) :: ReqDnsimple.Response.result(nil)
  def delete(req, template, record_id) do
    ReqDnsimple.Client.with_account(req, &delete(req, &1, template, record_id))
  end

  @doc """
  Deletes one record from a DNS template.

  The template may be a short name or integer ID. This sends exactly one
  bodyless request and returns `{:ok, {nil, metadata}}` only for HTTP 204.
  """
  @spec delete(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) :: ReqDnsimple.Response.result(nil)
  def delete(req, account_id, template, record_id) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template, record_id: record_id],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/templates/:template/records/:record_id",
          path_params_style: :colon,
          path_params: [
            account_id: account_id,
            template: template,
            record_id: record_id
          ],
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

  defp decode_many(data) when is_list(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, records} ->
      case decode(item) do
        {:ok, record} -> {:cont, {:ok, [record | records]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      :error -> :error
    end
  end

  defp decode_many(_data), do: :error

  defp request_list(req, account_id, template, opts) do
    params =
      opts
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> ReqDnsimple.Helper.merge(
      method: :get,
      url: "/:account_id/templates/:template/records",
      path_params_style: :colon,
      path_params: [account_id: account_id, template: template],
      params: params
    )
    |> Req.request()
  end

  defp validate_record_type(type) do
    if String.upcase(type, :ascii) in @record_types do
      :ok
    else
      {:error,
       %NimbleOptions.ValidationError{
         message: "expected :type to be a supported template record type (case-insensitive)",
         key: :type,
         value: type
       }}
    end
  end

  defp decode(%{
         "id" => id,
         "template_id" => template_id,
         "name" => name,
         "content" => content,
         "ttl" => ttl,
         "priority" => priority,
         "type" => type,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(template_id) and is_binary(name) and
              is_binary(content) and is_integer(ttl) and ttl >= 0 and type in @record_types and
              is_binary(created_at) and is_binary(updated_at) do
    with {:ok, priority} <- parse_priority(priority),
         {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         template_id: template_id,
         name: name,
         content: content,
         ttl: ttl,
         priority: priority,
         type: type,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _ -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_priority(priority) when is_integer(priority) or is_nil(priority),
    do: {:ok, priority}

  defp parse_priority(priority) when is_binary(priority) do
    if Regex.match?(@numeric_priority, priority) do
      {:ok, String.to_integer(priority)}
    else
      :error
    end
  end

  defp parse_priority(_priority), do: :error

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end
end
