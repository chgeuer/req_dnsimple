defmodule ReqDnsimple.TemplateRecord do
  @moduledoc """
  Operations for records in DNS templates.

  Create one template record with a flat attribute list:

      {:ok, record} =
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

      {:ok, record} =
        ReqDnsimple.TemplateRecord.get(
          client,
          1010,
          "offline-template",
          1
        )

  Delete one template record:

      :ok =
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
    type: [type: {:in, @record_types}, required: true],
    content: [type: :string, required: true],
    ttl: [type: :non_neg_integer],
    priority: [type: :integer]
  ]

  @doc """
  Creates one record in a DNS template.

  The template may be a short name or integer ID. Attributes are sent as a
  flat JSON object; `name`, `type`, and `content` are required, while `ttl`
  and `priority` are optional. Empty apex names, literal placeholders, and
  explicit zero values are preserved. This sends exactly one request.
  """
  @spec create(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) :: {:ok, t()} | {:error, term()}
  def create(req, account_id, template, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @create_path_schema
           ),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @create_schema) do
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
            {:ok, record} -> {:ok, record}
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
        ) :: {:ok, t()} | {:error, term()}
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
            {:ok, record} -> {:ok, record}
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
  Deletes one record from a DNS template.

  The template may be a short name or integer ID. This sends exactly one
  bodyless request and returns `:ok` only for HTTP 204.
  """
  @spec delete(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          integer()
        ) :: :ok | {:error, term()}
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
