defmodule ReqDnsimple.Response do
  @moduledoc """
  The shared result interface for HTTP operations.

  Success is `{:ok, {data, metadata}}`, including `nil` data for bodyless
  success. Failure is `{:error, %ReqDnsimple.Error{}}`, with the original
  reason and any available HTTP metadata.
  """

  alias ReqDnsimple.{Error, Metadata}

  @type result(data) :: {:ok, {data, Metadata.t()}} | {:error, Error.t()}

  @doc false
  @spec ok(data, Req.Response.t() | Metadata.t()) :: {:ok, {data, Metadata.t()}}
        when data: term()
  def ok(data, %Metadata{} = metadata), do: {:ok, {data, metadata}}
  def ok(data, %Req.Response{} = response), do: ok(data, Metadata.from_response(response))

  @doc false
  @spec error(term(), Req.Response.t() | Metadata.t() | nil) :: {:error, Error.t()}
  def error(reason, context \\ nil)
  def error(%Error{} = error, nil), do: {:error, error}

  def error(%Error{} = error, context) do
    {:error, %{error | metadata: metadata(context)}}
  end

  def error(reason, context) do
    {:error, %Error{reason: reason, metadata: metadata(context)}}
  end

  @doc false
  @spec normalize_error(result(data) | {:error, term()}) :: result(data) when data: term()
  def normalize_error({:error, reason}), do: error(reason)
  def normalize_error(result), do: result

  @doc false
  @spec error_after_pages(Error.t(), [Metadata.t()]) :: {:error, Error.t()}
  def error_after_pages(%Error{} = error, prior_pages) do
    error(error, Metadata.for_error(error.metadata, prior_pages))
  end

  defp metadata(nil), do: nil
  defp metadata(%Metadata{} = metadata), do: metadata
  defp metadata(%Req.Response{} = response), do: Metadata.from_response(response)
end
