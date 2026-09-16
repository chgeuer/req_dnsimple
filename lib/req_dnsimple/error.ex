defmodule ReqDnsimple.Error do
  @moduledoc """
  Failure returned by an HTTP operation or raised by its bang counterpart.

  The original error is available in `:reason`, including any HTTP status,
  response body, validation exception, or transport exception. Response metadata
  is available in `:metadata`, or is `nil` when no HTTP response was received.
  Enumeration failures retain metadata for earlier pages.

  The exception message does not include response bodies or metadata values.
  """

  defexception [:reason, :metadata]

  @type t :: %__MODULE__{reason: term(), metadata: ReqDnsimple.Metadata.t() | nil}

  @impl true
  def message(%__MODULE__{reason: :missing_account_id}),
    do: "DNSimple account_id is required; configure it with new_client/2 or for_account/2"

  def message(%__MODULE__{reason: :not_found}), do: "DNSimple resource not found"

  def message(%__MODULE__{reason: %{status: status}}) when is_integer(status),
    do: "DNSimple request failed with HTTP status #{status}"

  def message(%__MODULE__{}), do: "DNSimple request failed"
end
