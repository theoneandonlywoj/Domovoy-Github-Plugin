defmodule DomovoyGithubPlugin.Runner.GetRepository do
  @moduledoc """
  Reads the repository of the checkout as GitHub knows it.

  The result holds the default branch, which a graph reads to target a pull
  request or to compare a branch.

  ## Inputs

    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Repository`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetRepository |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_repository"}
      iex> DomovoyGithubPlugin.Runner.GetRepository.run(input, context)
      {:ok, %{full_name: "owner/repo", default_branch: "main", private: false, url: "https://github.com/owner/repo"}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError

  input do
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{working_directory: directory}, %Context{node: node_name}) do
    with {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory) do
      repo.owner
      |> GithubCapabilities.get_repository(repo.repo, directory)
      |> repository(node_name)
    end
  end

  @spec repository(result :: GithubCapabilities.result(), node_name :: Node.name()) ::
          {:ok, map()} | {:error, Error.t()}
  defp repository({:ok, %{"full_name" => name, "default_branch" => branch} = entry}, _node_name)
       when is_binary(name) and is_binary(branch) do
    {:ok,
     %{
       full_name: name,
       default_branch: branch,
       private: entry["private"] == true,
       url: entry["html_url"]
     }}
  end

  defp repository({:ok, body}, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :working_directory)}

  defp repository({:error, failure}, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :working_directory)}
end
