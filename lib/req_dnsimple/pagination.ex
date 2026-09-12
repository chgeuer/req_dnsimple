defmodule ReqDnsimple.Pagination do
  @moduledoc false

  @type metadata :: %{binary() => non_neg_integer()}

  @spec all(keyword(), (keyword() -> {:ok, {[term()], metadata()}} | {:error, term()})) ::
          {:ok, [term()]} | {:error, term()}
  def all(opts, fetch_page) when is_function(fetch_page, 1) do
    with {:ok, opts} <- ReqDnsimple.validate_keyword_list(opts) do
      if Keyword.has_key?(opts, :page) do
        {:error, {:invalid_option, :page}}
      else
        fetch_all(opts, fetch_page, 1, nil, [])
      end
    end
  end

  defp fetch_all(opts, fetch_page, page, expected_total_pages, items) do
    case fetch_page.(Keyword.put(opts, :page, page)) do
      {:ok, {page_items, pagination}} ->
        with {:ok, total_pages} <-
               validate(pagination, page, expected_total_pages) do
          accumulated = Enum.reverse(page_items, items)

          if page >= total_pages do
            {:ok, Enum.reverse(accumulated)}
          else
            fetch_all(opts, fetch_page, page + 1, total_pages, accumulated)
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate(
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
              per_page > 0 and is_integer(total_entries) and total_entries >= 0 and
              is_integer(total_pages) and total_pages >= 0 do
    valid_current_page? =
      current_page == requested_page and
        ((total_pages == 0 and requested_page == 1) or current_page <= total_pages)

    valid_total_pages? =
      is_nil(expected_total_pages) or total_pages == expected_total_pages

    if valid_current_page? and valid_total_pages? do
      {:ok, total_pages}
    else
      {:error, {:invalid_pagination, pagination}}
    end
  end

  defp validate(pagination, _requested_page, _expected_total_pages),
    do: {:error, {:invalid_pagination, pagination}}
end
