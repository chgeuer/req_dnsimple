defmodule ReqDnsimple.Helper do
  @moduledoc """
  Helper functions for Req HTTP client operations.
  """
  @doc """
  Appends URL path segments and merges various parameter types.
  """
  def append(req, opts) do
    req
    |> maybe_append_url(opts[:url])
    |> maybe_merge_params(opts[:params])
    |> maybe_merge_path_params(opts[:path_params])
  end

  defp maybe_append_url(req, nil), do: req

  defp maybe_append_url(req, path_segment) do
    updated_url = append_path_to_url(req.url, path_segment)
    Map.put(req, :url, updated_url)
  end

  defp maybe_merge_params(req, nil), do: req

  defp maybe_merge_params(req, new_params) do
    existing_params = req.options[:params] || []
    merged_params = merge_params(existing_params, new_params)
    Req.merge(req, params: merged_params)
  end

  defp maybe_merge_path_params(req, nil), do: req

  defp maybe_merge_path_params(req, new_path_params) do
    existing_path_params = req.options[:path_params] || []
    merged_path_params = merge_params(existing_path_params, new_path_params)
    Req.merge(req, path_params: merged_path_params)
  end

  defp merge_params(existing, new) when is_map(existing) and is_map(new) do
    Map.merge(existing, new)
  end

  defp merge_params(existing, new) when is_list(existing) and is_list(new) do
    if keyword_list?(existing) and keyword_list?(new) do
      Keyword.merge(existing, new)
    else
      # Handle tuple lists (what Req uses internally)
      existing ++ new
    end
  end

  defp merge_params(existing, new) when is_list(existing) and is_map(new) do
    if keyword_list?(existing) do
      Keyword.merge(existing, Map.to_list(new))
    else
      # existing is tuple list, convert map to tuple list
      existing ++ Map.to_list(new)
    end
  end

  defp merge_params(existing, new) when is_map(existing) and is_list(new) do
    Map.merge(existing, Map.new(new))
  end

  defp keyword_list?(list) do
    Enum.all?(list, fn
      {key, _value} when is_atom(key) -> true
      _ -> false
    end)
  end

  defp append_path_to_url(%URI{} = uri, path_segment) do
    clean_segment = String.trim_leading(path_segment, "/")
    existing_path = String.trim_trailing(uri.path || "", "/")

    new_path =
      case {existing_path, clean_segment} do
        {"", segment} -> "/" <> segment
        {path, segment} -> path <> "/" <> segment
      end

    %{uri | path: new_path}
  end
end
