defmodule DomovoyGithubPlugin.Type.Repository do
  @moduledoc """
  `DomovoyCore.Type` for a repository as GitHub knows it.

  `full_name` is `owner/repo`. `default_branch` is the branch a pull request
  targets when nothing else is named.

  ## Examples

  `dump/1` and `load/1` round-trip a value through a document:

      iex> state = %{full_name: "owner/repo", default_branch: "main", private: true, url: "u"}
      iex> {:ok, document} = DomovoyGithubPlugin.Type.Repository.dump(state)
      iex> document["default_branch"]
      "main"
      iex> DomovoyGithubPlugin.Type.Repository.load(document)
      {:ok, state}
  """

  use DomovoyCore.Type

  @typedoc "A repository."
  @type state() :: %{
          full_name: String.t(),
          default_branch: String.t(),
          private: boolean(),
          url: String.t() | nil
        }

  @impl Ecto.Type
  def type, do: :map

  @impl DomovoyCore.Type
  @spec cast(raw :: any(), metadata :: DomovoyCore.Type.metadata()) :: DomovoyCore.Type.cast()
  def cast(%{full_name: name, default_branch: branch, private: private, url: url} = state, _meta)
      when is_binary(name) and is_binary(branch) and is_boolean(private) and
             (is_binary(url) or is_nil(url)),
      do: {:ok, state}

  def cast(_raw, _metadata), do: :error

  @keys [:full_name, :default_branch, :private, :url]

  @impl Ecto.Type
  @spec load(document :: any()) :: {:ok, state()} | :error
  def load(document) when is_map(document),
    do: document |> DomovoyCore.Type.atom_keys(@keys) |> cast()

  def load(_document), do: :error
end
