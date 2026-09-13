defmodule ReqDnsimple.DnsAnalytics do
  @moduledoc """
  DNS query-volume analytics for an account.

  Analytics are returned as headers plus ordered tabular rows. `list_page/3`
  and `query/3` make one request and include the server pagination map.
  `list_all/3` explicitly enumerates compatible pages and retains the first
  page's query as provenance.

  ## Example

      ReqDnsimple.DnsAnalytics.list_page(req, 1010,
        start_date: "2026-09-01",
        end_date: "2026-09-02",
        groupings: [:date, :zone_name],
        sort: [date: :asc, zone_name: :desc],
        page: 2,
        per_page: 1
      )
      #=> {:ok, {%ReqDnsimple.DnsAnalytics.Result{}, %{"current_page" => 2}}}
  """

  defmodule Query do
    @moduledoc """
    Query metadata echoed by the DNS analytics endpoint.
    """

    @type t :: %__MODULE__{
            account_id: integer(),
            start_date: Date.t() | nil,
            end_date: Date.t() | nil,
            sort: binary(),
            groupings: binary() | nil,
            page: integer(),
            per_page: integer()
          }

    defstruct ~w(account_id start_date end_date sort groupings page per_page)a
  end

  defmodule Result do
    @moduledoc """
    Typed tabular DNS analytics response.
    """

    @type cell :: integer() | binary()
    @type t :: %__MODULE__{
            headers: [binary()],
            rows: [[cell()]],
            query: ReqDnsimple.DnsAnalytics.Query.t()
          }

    defstruct ~w(headers rows query)a
  end

  alias __MODULE__.{Query, Result}

  @path_schema [
    account_id: [type: :integer, required: true]
  ]

  @list_schema [
    start_date: [
      type: {:custom, __MODULE__, :validate_date, []},
      doc: "Inclusive start date in YYYY-MM-DD format"
    ],
    end_date: [
      type: {:custom, __MODULE__, :validate_date, []},
      doc: "Inclusive end date in YYYY-MM-DD format"
    ],
    groupings: [
      type: {:list, {:in, [:date, :zone_name]}},
      doc: "Ordered date and zone_name groupings"
    ],
    sort: [
      type: {:custom, ReqDnsimple, :validate_sort, [[:date, :zone_name, :volume]]},
      doc: "Sort by date, zone_name, or volume"
    ],
    page: [type: :pos_integer, doc: "Page number for pagination"],
    per_page: [type: {:in, 1..10_000}, doc: "Number of analytics rows per page"]
  ]

  @doc """
  Queries one page of DNS analytics.

  Dates use `YYYY-MM-DD`; when both are present their inclusive span may not
  exceed 31 days. Groupings accept `:date` and `:zone_name`, while sorting also
  accepts `:volume`. Multiple terms retain caller order.
  """
  @spec list_page(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {Result.t(), ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def list_page(req, account_id, opts \\ []) do
    with {:ok, _validated_path} <-
           NimbleOptions.validate([account_id: account_id], @path_schema),
         {:ok, validated_opts} <- ReqDnsimple.validate_options(opts, @list_schema),
         :ok <- validate_date_range(validated_opts) do
      case request_page(req, account_id, validated_opts) do
        {:ok,
         %Req.Response{
           status: 200,
           body: %{"data" => data, "query" => query, "pagination" => pagination}
         } = response} ->
          case decode_page(data, query, pagination) do
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
  Queries one page of DNS analytics.

  This is a convenience alias for `list_page/3` and never enumerates
  additional pages.
  """
  @spec query(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, {Result.t(), ReqDnsimple.Pagination.metadata()}} | {:error, term()}
  def query(req, account_id, opts \\ []), do: list_page(req, account_id, opts)

  @doc """
  Enumerates all compatible DNS analytics pages in server order.

  Enumeration starts at page one and rejects an explicit `:page`. The returned
  result retains the first page's headers and query metadata.
  """
  @spec list_all(Req.Request.t(), ReqDnsimple.account_id(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def list_all(req, account_id, opts \\ []) do
    with {:ok, opts} <- ReqDnsimple.validate_keyword_list(opts) do
      if Keyword.has_key?(opts, :page) do
        {:error, {:invalid_option, :page}}
      else
        fetch_all(req, account_id, opts, 1, nil, nil)
      end
    end
  end

  @doc false
  @spec validate_date(term()) :: {:ok, binary()} | {:error, binary()}
  def validate_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _date} -> {:ok, value}
      {:error, _reason} -> {:error, "expected an ISO8601 date in YYYY-MM-DD format"}
    end
  end

  def validate_date(_value), do: {:error, "expected an ISO8601 date in YYYY-MM-DD format"}

  defp fetch_all(req, account_id, opts, page, expected_total_pages, accumulator) do
    case list_page(req, account_id, Keyword.put(opts, :page, page)) do
      {:ok, {result, pagination}} ->
        with {:ok, total_pages} <-
               validate_enumeration_pagination(pagination, page, expected_total_pages),
             {:ok, accumulator} <- append_page(accumulator, result) do
          if page >= total_pages do
            {:ok, accumulator}
          else
            fetch_all(req, account_id, opts, page + 1, total_pages, accumulator)
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_page(nil, result), do: {:ok, result}

  defp append_page(%Result{headers: headers}, %Result{headers: next_headers})
       when headers != next_headers,
       do: {:error, {:incompatible_page, :headers}}

  defp append_page(%Result{query: query}, %Result{query: next_query})
       when query.account_id != next_query.account_id or query.start_date != next_query.start_date or
              query.end_date != next_query.end_date or query.sort != next_query.sort or
              query.groupings != next_query.groupings or query.per_page != next_query.per_page,
       do: {:error, {:incompatible_page, :query}}

  defp append_page(%Result{} = result, %Result{} = next_result) do
    {:ok, %{result | rows: result.rows ++ next_result.rows}}
  end

  defp validate_date_range(opts) do
    case {Keyword.get(opts, :start_date), Keyword.get(opts, :end_date)} do
      {start_date, end_date} when is_binary(start_date) and is_binary(end_date) ->
        {:ok, start_date} = Date.from_iso8601(start_date)
        {:ok, end_date} = Date.from_iso8601(end_date)
        days = Date.diff(end_date, start_date)

        if days in 0..30 do
          :ok
        else
          validation_error("expected an inclusive date range of at most 31 days", opts)
        end

      _other ->
        :ok
    end
  end

  defp request_page(req, account_id, opts) do
    params =
      opts
      |> encode_groupings()
      |> ReqDnsimple.convert_sort_to_string()
      |> Map.new()

    req
    |> Req.merge(
      method: :get,
      url: "/:account_id/dns_analytics",
      path_params_style: :colon,
      path_params: [account_id: account_id],
      params: params
    )
    |> Req.request()
  end

  defp encode_groupings(opts) do
    case Keyword.fetch(opts, :groupings) do
      {:ok, groupings} -> Keyword.put(opts, :groupings, Enum.join(groupings, ","))
      :error -> opts
    end
  end

  defp decode_page(data, query, pagination) do
    with {:ok, result} <- decode_result(data, query),
         true <- valid_pagination?(pagination) do
      {:ok, {result, pagination}}
    else
      _invalid -> :error
    end
  end

  defp decode_result(%{"headers" => headers, "rows" => rows}, query) when is_list(headers) do
    with true <- Enum.all?(headers, &is_binary/1),
         true <- valid_rows?(rows, length(headers)),
         {:ok, query} <- decode_query(query) do
      {:ok, %Result{headers: headers, rows: rows, query: query}}
    else
      _invalid -> :error
    end
  end

  defp decode_result(_data, _query), do: :error

  defp decode_query(%{
         "account_id" => account_id,
         "start_date" => start_date,
         "end_date" => end_date,
         "sort" => sort,
         "groupings" => groupings,
         "page" => page,
         "per_page" => per_page
       })
       when is_integer(account_id) and is_binary(sort) and
              (is_binary(groupings) or is_nil(groupings)) and is_integer(page) and
              is_integer(per_page) do
    with {:ok, start_date} <- parse_optional_date(start_date),
         {:ok, end_date} <- parse_optional_date(end_date) do
      {:ok,
       %Query{
         account_id: account_id,
         start_date: start_date,
         end_date: end_date,
         sort: sort,
         groupings: groupings,
         page: page,
         per_page: per_page
       }}
    else
      _invalid -> :error
    end
  end

  defp decode_query(_query), do: :error

  defp valid_rows?(rows, header_count) when is_list(rows) do
    Enum.all?(rows, fn
      row when is_list(row) ->
        length(row) == header_count and Enum.all?(row, &(is_integer(&1) or is_binary(&1)))

      _other ->
        false
    end)
  end

  defp valid_rows?(_rows, _header_count), do: false

  defp valid_pagination?(%{
         "current_page" => current_page,
         "per_page" => per_page,
         "total_entries" => total_entries,
         "total_pages" => total_pages
       })
       when is_integer(current_page) and current_page >= 0 and is_integer(per_page) and
              per_page >= 0 and is_integer(total_entries) and total_entries >= 0 and
              is_integer(total_pages) and total_pages >= 0,
       do: true

  defp valid_pagination?(_pagination), do: false

  defp validate_enumeration_pagination(
         %{
           "current_page" => current_page,
           "per_page" => per_page,
           "total_entries" => total_entries,
           "total_pages" => total_pages
         } = pagination,
         requested_page,
         expected_total_pages
       )
       when is_integer(current_page) and current_page >= 0 and is_integer(per_page) and
              per_page >= 0 and is_integer(total_entries) and total_entries >= 0 and
              is_integer(total_pages) and total_pages >= 0 do
    valid_current_page? =
      current_page == requested_page and
        ((total_pages == 0 and requested_page == 1) or current_page <= total_pages)

    valid_total_pages? = is_nil(expected_total_pages) or total_pages == expected_total_pages

    if valid_current_page? and valid_total_pages? do
      {:ok, total_pages}
    else
      {:error, {:invalid_pagination, pagination}}
    end
  end

  defp validate_enumeration_pagination(pagination, _requested_page, _expected_total_pages),
    do: {:error, {:invalid_pagination, pagination}}

  defp parse_optional_date(nil), do: {:ok, nil}

  defp parse_optional_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> :error
    end
  end

  defp parse_optional_date(_value), do: :error

  defp validation_error(message, value) do
    {:error, %NimbleOptions.ValidationError{message: message, value: value}}
  end
end
