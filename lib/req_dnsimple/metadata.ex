defmodule ReqDnsimple.Metadata do
  @moduledoc """
  Metadata returned alongside data from a DNSimple HTTP operation.

  Rate-limit values are non-negative integers. `rate_limit_reset` is a Unix
  timestamp in seconds. Request IDs, ETags, and `retry_after` retain their exact
  header values; Retry-After can be either a delay or an HTTP date.

  Missing values are `nil`. Malformed values are recorded in `parse_errors`
  without turning an otherwise successful operation into a failure.

  Complete enumeration retains each page's metadata in `pages`, in request
  order. Its top-level rate-limit and Retry-After values come from the last
  page. Aggregate status, pagination, request ID, and ETag are `nil`: no single
  HTTP response or ETag represents the combined collection.
  """

  @type pagination :: %{binary() => term()}
  @type parse_error :: {:invalid_header, term()} | {:invalid_pagination, term()}
  @type t :: %__MODULE__{
          status: non_neg_integer() | nil,
          pagination: pagination() | nil,
          rate_limit: non_neg_integer() | nil,
          rate_limit_remaining: non_neg_integer() | nil,
          rate_limit_reset: non_neg_integer() | nil,
          request_id: binary() | nil,
          etag: binary() | nil,
          retry_after: binary() | nil,
          pages: [t()],
          parse_errors: %{atom() => parse_error()}
        }

  defstruct [
    :status,
    :pagination,
    :rate_limit,
    :rate_limit_remaining,
    :rate_limit_reset,
    :request_id,
    :etag,
    :retry_after,
    pages: [],
    parse_errors: %{}
  ]

  @headers [
    {:rate_limit, "x-ratelimit-limit", :integer},
    {:rate_limit_remaining, "x-ratelimit-remaining", :integer},
    {:rate_limit_reset, "x-ratelimit-reset", :integer},
    {:request_id, "x-request-id", :string},
    {:etag, "etag", :string},
    {:retry_after, "retry-after", :string}
  ]

  @doc "Extracts metadata from the HTTP response returned by Req."
  @spec from_response(Req.Response.t()) :: t()
  def from_response(%Req.Response{} = response) do
    headers =
      Enum.reduce(response.headers, %{}, fn {name, values}, headers ->
        Map.update(headers, name |> to_string() |> String.downcase(), List.wrap(values), fn old ->
          old ++ List.wrap(values)
        end)
      end)

    Enum.reduce(@headers, %__MODULE__{status: response.status}, fn {field, name, type},
                                                                   metadata ->
      case decode_header(Map.get(headers, name, []), type) do
        {:ok, value} -> Map.put(metadata, field, value)
        {:error, reason} -> put_error(metadata, field, reason)
      end
    end)
    |> put_pagination(response.body)
  end

  @doc "Combines metadata from a non-empty, ordered list of page responses."
  @spec aggregate(nonempty_list(t())) :: t()
  def aggregate([%__MODULE__{} | _] = pages) do
    %{
      List.last(pages)
      | status: nil,
        pagination: nil,
        request_id: nil,
        etag: nil,
        pages: pages
    }
  end

  @doc """
  Retains prior page metadata when enumeration fails.

  An HTTP failure appends its own metadata and keeps its status and request
  identifiers. A failure without an HTTP response retains the completed
  pages, or returns `nil` if no response was received.
  """
  @spec for_error(t() | nil, [t()]) :: t() | nil
  def for_error(%__MODULE__{} = failed_response, prior_pages) do
    %{failed_response | pages: prior_pages ++ [failed_response]}
  end

  def for_error(nil, []), do: nil
  def for_error(nil, prior_pages), do: aggregate(prior_pages)

  defp decode_header([], _type), do: {:ok, nil}
  defp decode_header([value], :string) when is_binary(value), do: {:ok, value}

  defp decode_header([value] = values, :integer) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _ -> {:error, {:invalid_header, values}}
    end
  end

  defp decode_header(values, _type), do: {:error, {:invalid_header, values}}

  defp put_pagination(metadata, %{"pagination" => nil}), do: metadata

  defp put_pagination(metadata, %{
         "pagination" =>
           %{
             "current_page" => current_page,
             "per_page" => per_page,
             "total_entries" => total_entries,
             "total_pages" => total_pages
           } = pagination
       })
       when is_integer(current_page) and current_page >= 0 and is_integer(per_page) and
              per_page >= 0 and is_integer(total_entries) and total_entries >= 0 and
              is_integer(total_pages) and total_pages >= 0 do
    %{metadata | pagination: pagination}
  end

  defp put_pagination(metadata, %{"pagination" => value}) do
    put_error(metadata, :pagination, {:invalid_pagination, value})
  end

  defp put_pagination(metadata, _body), do: metadata

  defp put_error(metadata, field, reason) do
    %{metadata | parse_errors: Map.put(metadata.parse_errors, field, reason)}
  end
end
