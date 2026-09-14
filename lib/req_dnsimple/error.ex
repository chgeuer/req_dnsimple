defmodule ReqDnsimple.Error do
  @moduledoc """
  Exception raised when a bang function encounters a non-exception error result.

  The original error is available in `:reason`, including any HTTP status,
  response body, and retry information. The exception message does not include
  response bodies. Existing validation and transport exceptions are raised
  unchanged instead of being wrapped.
  """

  defexception [:reason]

  @type t :: %__MODULE__{reason: term()}

  @impl true
  def message(%__MODULE__{reason: :missing_account_id}),
    do: "DNSimple account_id is required; configure it with new_client/2 or for_account/2"

  def message(%__MODULE__{reason: :not_found}), do: "DNSimple resource not found"

  def message(%__MODULE__{reason: %{status: status}}) when is_integer(status),
    do: "DNSimple request failed with HTTP status #{status}"

  def message(%__MODULE__{}), do: "DNSimple request failed"
end
