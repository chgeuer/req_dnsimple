defmodule ReqDnsimple.Template do
  @moduledoc """
  DNS template operations.

  Create an account template:

      {:ok, template} =
        ReqDnsimple.Template.create(
          client,
          1010,
          sid: "offline-template",
          name: "Offline template",
          description: "Offline contract example"
        )

  Creating a template sends exactly one request. It does not create template
  records or apply the template to a domain.

  Update only the supplied template metadata:

      {:ok, template} =
        ReqDnsimple.Template.update(
          client,
          1010,
          "offline-template",
          description: ""
        )

  The path uses the supplied current short name or ID even when `:sid` changes.

  List one page or deliberately enumerate every page:

      {:ok, {templates, pagination}} =
        ReqDnsimple.Template.list_page(
          client,
          1010,
          sort: [id: :asc, name: :desc],
          page: 2,
          per_page: 30
        )

      {:ok, templates} =
        ReqDnsimple.Template.list_all(
          client,
          1010,
          sort: [sid: :asc]
        )

  Retrieve an account template by short name or ID:

      {:ok, template} =
        ReqDnsimple.Template.get(
          client,
          1010,
          "offline-template"
        )

  Apply an account template to a domain:

      :ok =
        ReqDnsimple.Template.apply(
          client,
          1010,
          "example.test",
          "offline-template"
        )

  Applying a template sends exactly one request. Record creation and placeholder
  expansion are performed by DNSimple.

  Delete an account template by short name or ID:

      :ok =
        ReqDnsimple.Template.delete(
          client,
          1010,
          "offline-template"
        )
  """

  @type t :: %__MODULE__{
          id: integer(),
          account_id: integer(),
          name: binary(),
          sid: binary(),
          description: binary(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id account_id name sid description created_at updated_at)a

  @path_schema [
    account_id: [type: :integer, required: true],
    domain: [type: {:or, [:string, :integer]}, required: true],
    template: [type: {:or, [:string, :integer]}, required: true]
  ]

  @template_path_schema Keyword.delete(@path_schema, :domain)
  @create_path_schema [account_id: [type: :integer, required: true]]
  @create_schema [
    sid: [type: :string, required: true],
    name: [type: :string, required: true],
    description: [type: :string]
  ]
  @update_schema [
    sid: [type: :string],
    name: [type: :string],
    description: [type: :string]
  ]
  @list_schema [
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:id, :name, :sid]]},
      doc: "Sort by id, name, or sid"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..100}, doc: "Number of templates per page"]
  ]

  @doc """
  Creates an account template from a required short identifier and name.

  The optional description is omitted unless explicitly supplied. This sends
  exactly one request and returns the created template with typed timestamps.
  It does not create records or apply the template to a domain.
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
          url: "/:account_id/templates",
          path_params_style: :colon,
          path_params: [account_id: account_id],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 201, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, template} -> {:ok, template}
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
  Updates the supplied metadata for an account template.

  All attributes are optional, and omitted attributes are not sent. The template
  path accepts its current short name or integer ID and is not changed when a new
  `:sid` is supplied. This sends exactly one request and returns the updated
  template with typed timestamps.
  """
  @spec update(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          keyword()
        ) :: {:ok, t()} | {:error, term()}
  def update(req, account_id, template, attrs) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @template_path_schema
           ),
         {:ok, validated_attrs} <- ReqDnsimple.validate_options(attrs, @update_schema) do
      req =
        Req.merge(req,
          method: :patch,
          url: "/:account_id/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, template: template],
          json: Map.new(validated_attrs),
          retry: false
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, template} -> {:ok, template}
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
  Lists one page of account templates.

  Supports ordered `:sort` terms for `:id`, `:name`, and `:sid`, plus `:page`
  and `:per_page`. The returned pagination metadata retains its string keys.
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
  Lists one page of account templates.

  This is a convenience alias for `list_page/3`; it never enumerates additional
  pages implicitly.
  """
  @spec list(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {[t()], ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list(req, account_id, opts \\ []), do: list_page(req, account_id, opts)

  @doc """
  Enumerates every page of account templates in server order.

  Enumeration always begins at page one, so an explicit `:page` option is
  rejected. Sorting and `:per_page` are retained for every request.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, [t()]} | {:error, term()}
  def list_all(req, account_id, opts \\ []) do
    ReqDnsimple.Pagination.all(opts, &list_page(req, account_id, &1))
  end

  @doc """
  Retrieves an account template by short name or ID.

  The returned template has typed timestamps. This sends exactly one bodyless
  request to the plural `/templates` endpoint.
  """
  @spec get(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          {:ok, t()} | {:error, term()}
  def get(req, account_id, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @template_path_schema
           ) do
      req =
        Req.merge(req,
          method: :get,
          url: "/:account_id/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, template: template]
        )

      case Req.request(req) do
        {:ok, %Req.Response{status: 200, body: %{"data" => data}} = response} ->
          case decode(data) do
            {:ok, template} -> {:ok, template}
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
  Applies a template to a domain.

  The domain and template may be a short name or integer ID. This sends exactly
  one bodyless request and returns `:ok` only for HTTP 204.
  """
  @spec apply(
          Req.Request.t(),
          ReqDnsimple.account_id(),
          binary() | integer(),
          binary() | integer()
        ) :: :ok | {:error, term()}
  def apply(req, account_id, domain, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, domain: domain, template: template],
             @path_schema
           ) do
      req =
        Req.merge(req,
          method: :post,
          url: "/:account_id/domains/:domain/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, domain: domain, template: template],
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

  @doc """
  Deletes an account template by short name or ID.

  This sends exactly one bodyless request and returns `:ok` only for HTTP 204.
  Templates already applied to domains are unaffected.
  """
  @spec delete(Req.Request.t(), ReqDnsimple.account_id(), binary() | integer()) ::
          :ok | {:error, term()}
  def delete(req, account_id, template) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate(
             [account_id: account_id, template: template],
             @template_path_schema
           ) do
      req =
        Req.merge(req,
          method: :delete,
          url: "/:account_id/templates/:template",
          path_params_style: :colon,
          path_params: [account_id: account_id, template: template],
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

  defp decode_page(data, pagination) when is_list(data) do
    with {:ok, templates} <- decode_many(data),
         true <- valid_pagination?(pagination) do
      {:ok, {templates, pagination}}
    else
      _error -> :error
    end
  end

  defp decode_page(_data, _pagination), do: :error

  defp decode_many(data) do
    Enum.reduce_while(data, {:ok, []}, fn item, {:ok, templates} ->
      case decode(item) do
        {:ok, template} -> {:cont, {:ok, [template | templates]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, templates} -> {:ok, Enum.reverse(templates)}
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
      url: "/:account_id/templates",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end

  defp decode(%{
         "id" => id,
         "account_id" => account_id,
         "name" => name,
         "sid" => sid,
         "description" => description,
         "created_at" => created_at,
         "updated_at" => updated_at
       })
       when is_integer(id) and is_integer(account_id) and is_binary(name) and is_binary(sid) and
              is_binary(description) and is_binary(created_at) and is_binary(updated_at) do
    with {:ok, created_at} <- parse_datetime(created_at),
         {:ok, updated_at} <- parse_datetime(updated_at) do
      {:ok,
       %__MODULE__{
         id: id,
         account_id: account_id,
         name: name,
         sid: sid,
         description: description,
         created_at: created_at,
         updated_at: updated_at
       }}
    else
      _ -> :error
    end
  end

  defp decode(_data), do: :error

  defp parse_datetime(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> :error
    end
  end
end
