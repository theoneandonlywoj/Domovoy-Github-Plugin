defmodule DomovoyGithubPlugin.Type.Config do
  @moduledoc """
  `DomovoyCore.Type` for the configuration map of GitHub.

  The raw value must be a map with an `"access_token"` that is not empty. The
  other fields are optional. `"default_base_branch"` names the target branch of
  a pull request when the caller names no branch. The two timeout fields replace
  the defaults of the request. An optional field that is not there becomes
  `nil`.
  """

  use DomovoyCore.Type

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(raw_value, _metadata) when is_map(raw_value) do
    case Map.get(raw_value, "access_token") do
      token when is_binary(token) ->
        if String.trim(token) == "", do: :error, else: {:ok, raw_value}

      _other ->
        :error
    end
  end

  def cast(_raw, _metadata), do: :error
end
