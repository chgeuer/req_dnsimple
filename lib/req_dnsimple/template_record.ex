defmodule ReqDnsimple.TemplateRecord do
  @moduledoc """
  Operations for records in DNS templates.

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
  @numeric_priority ~r/^[0-9]+$/

  @path_schema [
    account_id: [type: :integer, required: true],
    template: [type: {:or, [:string, :integer]}, required: true],
    record_id: [type: :integer, required: true]
  ]

  @doc """
  Retrieves one record from a DNS template.

  The template may be a short name or integer ID. This sends exactly one
  bodyless request and returns a typed record with parsed timestamps.
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
