defmodule ReqDnsimple.NsRecord do
  @moduledoc """
  DNSimple Name Server Record structure.
  """
  @type t :: %__MODULE__{
          id: ReqDnsimple.record_id(),
          zone_id: ReqDnsimple.zone_id(),
          parent_id: integer() | nil,
          name: binary(),
          content: binary(),
          ttl: integer(),
          priority: integer() | nil,
          type: binary(),
          regions: [binary()],
          system_record: boolean(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct ~w(id zone_id parent_id name content ttl priority type regions system_record created_at updated_at)a

  @spec from_json(map()) :: t()
  def from_json(json) do
    ReqDnsimple.from_json(json, __MODULE__,
      regular: ~w[id zone_id parent_id name content ttl priority type regions system_record],
      datetime: ~w[created_at updated_at]
    )
  end
end
