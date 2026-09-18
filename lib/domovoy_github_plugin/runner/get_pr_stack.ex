defmodule DomovoyGithubPlugin.Runner.GetPrStack do
  @moduledoc """
  Reads the stack that a pull request belongs to.

  The pull request is the one that `number` names, or the open one of the
  current branch. The runner walks up: while the base of a pull request is
  not the default branch, it finds the open pull request of that base. It
  walks down: it finds the newest open pull request whose base is the head of
  the current one, and repeats. The result lists the chain from the root to
  the leaf.

  A pull request whose base has no open pull request is the root, even when
  that base is not the default branch. A chain that loops, or one deeper than
  #{50} pull requests in one direction, gives `:github_stack_cycle_detected`.

  ## Inputs

    * `number` — optional. A `DomovoyCore.Type.Integer`. Without it the runner
      starts from the open pull request of the current branch.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.Stack`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.GetPrStack |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "get_pr_stack"}
      iex> DomovoyGithubPlugin.Runner.GetPrStack.run(input, context)
      {:ok,
       %{
         base: "main",
         current: 43,
         pulls: [
           %{number: 42, head: "feat-a", base: "main", url: "https://github.com/owner/repo/pull/42"},
           %{number: 43, head: "feat-b", base: "feat-a", url: "https://github.com/owner/repo/pull/43"}
         ]
       }}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError

  @max_depth 50

  @typep walk() :: %{
           repo: GithubCapabilities.repo(),
           default: String.t(),
           directory: String.t(),
           node_name: Node.name()
         }

  input do
    field(:number, IntegerType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{number: number, working_directory: directory}, %Context{node: node_name}) do
    with {:ok, target} <- GithubCapabilities.resolve_pull(number, directory, node_name, :number),
         {:ok, default} <- default_branch(target.repo, directory, node_name) do
      walk = %{repo: target.repo, default: default, directory: directory, node_name: node_name}
      visited = [head_of(target.pull)]

      with {:ok, parents} <- parents(walk, target.pull, visited, []),
           {:ok, children} <- children(walk, target.pull, visited, []) do
        pulls = Enum.map(parents ++ [target.pull] ++ children, &entry/1)
        {:ok, %{base: default, current: target.number, pulls: pulls}}
      end
    end
  end

  @spec default_branch(
          repo :: GithubCapabilities.repo(),
          directory :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, String.t()} | {:error, Error.t()}
  defp default_branch(repo, directory, node_name) do
    case GithubCapabilities.get_repository(repo.owner, repo.repo, directory) do
      {:ok, %{"default_branch" => default}} when is_binary(default) -> {:ok, default}
      {:ok, body} -> {:error, GithubError.request_failed(inspect(body), node_name, :number)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, node_name, :number)}
    end
  end

  @spec parents(walk :: walk(), pull :: map(), visited :: [String.t()], acc :: [map()]) ::
          {:ok, [map()]} | {:error, Error.t()}
  defp parents(walk, pull, visited, acc) do
    base = base_of(pull)

    cond do
      base == walk.default -> {:ok, acc}
      base in visited or length(visited) > @max_depth -> cycle(walk, visited, base)
      true -> parent(walk, base, visited, acc)
    end
  end

  @spec parent(walk :: walk(), base :: String.t(), visited :: [String.t()], acc :: [map()]) ::
          {:ok, [map()]} | {:error, Error.t()}
  defp parent(walk, base, visited, acc) do
    head = "#{walk.repo.owner}:#{base}"

    case GithubCapabilities.list_open_pulls(walk.repo.owner, walk.repo.repo, head, walk.directory) do
      {:ok, [pull | _rest]} when is_map(pull) ->
        parents(walk, pull, [base | visited], [pull | acc])

      {:ok, []} ->
        {:ok, acc}

      {:ok, body} ->
        {:error, GithubError.request_failed(inspect(body), walk.node_name, :number)}

      {:error, failure} ->
        {:error, GithubError.request_failed(failure, walk.node_name, :number)}
    end
  end

  @spec children(walk :: walk(), pull :: map(), visited :: [String.t()], acc :: [map()]) ::
          {:ok, [map()]} | {:error, Error.t()}
  defp children(walk, pull, visited, acc) do
    head = head_of(pull)

    walk.repo.owner
    |> GithubCapabilities.list_pulls_by_base(walk.repo.repo, head, "open", walk.directory)
    |> case do
      {:ok, [child | _rest]} when is_map(child) -> child(walk, child, visited, acc)
      {:ok, []} -> {:ok, Enum.reverse(acc)}
      {:ok, body} -> {:error, GithubError.request_failed(inspect(body), walk.node_name, :number)}
      {:error, failure} -> {:error, GithubError.request_failed(failure, walk.node_name, :number)}
    end
  end

  @spec child(walk :: walk(), child :: map(), visited :: [String.t()], acc :: [map()]) ::
          {:ok, [map()]} | {:error, Error.t()}
  defp child(walk, child, visited, acc) do
    head = head_of(child)

    if head in visited or length(visited) > @max_depth,
      do: cycle(walk, visited, head),
      else: children(walk, child, [head | visited], [child | acc])
  end

  @spec cycle(walk :: walk(), visited :: [String.t()], branch :: String.t()) ::
          {:error, Error.t()}
  defp cycle(walk, visited, branch) do
    branches = Enum.reverse(visited) ++ [branch]
    {:error, GithubError.stack_cycle_detected(branches, walk.node_name, :number)}
  end

  @spec entry(pull :: map()) :: map()
  defp entry(pull),
    do: %{number: pull["number"], head: head_of(pull), base: base_of(pull), url: pull["html_url"]}

  @spec head_of(pull :: map()) :: String.t()
  defp head_of(pull), do: get_in(pull, ["head", "ref"]) || ""

  @spec base_of(pull :: map()) :: String.t()
  defp base_of(pull), do: get_in(pull, ["base", "ref"]) || ""
end
