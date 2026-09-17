defmodule DomovoyGithubPlugin.Runner.ReadConfig do
  @moduledoc """
  Reads and checks the GitHub configuration of a workflow.

  The runner finds `.domovoy/config/github.json` when it moves up from the
  working directory. Therefore a linked worktree gets the repository config.

  ## Inputs

    * `config` — optional. A `DomovoyGithubPlugin.Type.Config` that replaces
      the file. Use this field in a test.
    * `config_path` — optional. A `DomovoyCore.Type.String` with the file path.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The search
      starts there. The default is the current directory.

  The runner reads `config` first, then `config_path`, then the search from
  `working_directory`.

  The node `:type` receives the configuration. Usually the type is
  `DomovoyGithubPlugin.Type.Config`.

  ## Examples

  This runner reads the disk, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.ReadConfig |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "read_github_config"}
      iex> DomovoyGithubPlugin.Runner.ReadConfig.run(input, context)
      {:ok,
       %{
         "access_token" => "ghp_...",
         "default_base_branch" => "main",
         "connect_timeout_ms" => nil,
         "receive_timeout_ms" => nil
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError
  alias DomovoyGithubPlugin.Type.Config, as: ConfigType

  input do
    field(:config, ConfigType)
    field(:config_path, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{config: %{} = config}, %Context{}), do: {:ok, config}

  def run(%Input{config_path: path}, %Context{node: node_name}) when is_binary(path),
    do: load_config(path, node_name, :config_path)

  def run(%Input{working_directory: directory}, %Context{node: node_name}) do
    directory
    |> GithubCapabilities.find_config_path()
    |> load_config(node_name, :working_directory)
  end

  @spec load_config(
          path :: String.t(),
          node_name :: Node.name(),
          field_name :: atom()
        ) :: Runner.result()
  defp load_config(path, node_name, field_name) do
    case GithubCapabilities.load_config(path) do
      {:ok, config} -> cast_config(config, path, node_name, field_name)
      :error -> {:error, GithubError.config_not_found(path, node_name, field_name)}
    end
  end

  @spec cast_config(
          config :: map(),
          path :: String.t(),
          node_name :: Node.name(),
          field_name :: atom()
        ) :: Runner.result()
  defp cast_config(config, path, node_name, field_name) do
    case Value.cast(config, ConfigType) do
      {:ok, %Value{value: value}} ->
        {:ok, value}

      {:error, %Error{} = error} ->
        context = %{path: path, node_name: node_name, field_name: field_name}
        {:error, %Error{error | metadata: Map.merge(error.metadata, context)}}
    end
  end
end
