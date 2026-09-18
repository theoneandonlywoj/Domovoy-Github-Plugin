defmodule DomovoyGithubPlugin.Runner.SetCommitStatus do
  @moduledoc """
  Sets a commit status on a commit.

  The commit is `sha`, or `HEAD` of the checkout. A status has a `context`
  that names it. A later status with the same context replaces the earlier
  one. Therefore a workflow reports its progress under one context.

  ## Inputs

    * `state` — necessary. A `DomovoyCore.Type.String`. It is `"error"`,
      `"failure"`, `"pending"`, or `"success"`.
    * `context` — optional. A `DomovoyCore.Type.String`. The default is
      `"domovoy"`.
    * `description` — optional. A `DomovoyCore.Type.String`. GitHub shows it
      next to the context.
    * `target_url` — optional. A `DomovoyCore.Type.String`. GitHub links the
      status to it.
    * `sha` — optional. A `DomovoyCore.Type.String`. The default is `HEAD`.
    * `working_directory` — optional. A `DomovoyCore.Type.Directory`. The default
      is the current directory.

  The node `:type` receives the result. Usually the type is
  `DomovoyGithubPlugin.Type.CommitStatus`.

  ## Examples

  This runner reads Git and calls GitHub, so this example is illustrative.

      iex> params = %{state: "success", description: "All good", working_directory: "/repo"}
      iex> input = DomovoyGithubPlugin.Runner.SetCommitStatus |> DomovoyCore.Runner.changeset(params) |> Ecto.Changeset.apply_changes()
      iex> context = %DomovoyCore.Context{job: DomovoyCore.Job.new("run"), node: "set_status"}
      iex> DomovoyGithubPlugin.Runner.SetCommitStatus.run(input, context)
      {:ok, %{sha: "abc123", state: "success", context: "domovoy", url: nil}}
  """

  use DomovoyCore.Runner

  alias DomovoyCore.Context
  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Runner
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyGithubPlugin.Capabilities, as: GithubCapabilities
  alias DomovoyGithubPlugin.Error, as: GithubError
  alias DomovoyGithubPlugin.Type.CommitStatus, as: CommitStatusType

  input do
    field(:state, StringType)
    field(:context, StringType, default: "domovoy")
    field(:description, StringType)
    field(:target_url, StringType)
    field(:sha, StringType)
    field(:working_directory, DirectoryType, default: ".")
  end

  required([:state, :context, :working_directory])

  @impl Runner
  @spec run(input :: Input.t(), context :: Context.t()) :: Runner.result()
  def run(%Input{} = input, %Context{node: node_name}) do
    directory = input.working_directory

    with {:ok, state} <- validated_state(input.state, node_name),
         {:ok, repo} <- GithubCapabilities.current_repo(directory, node_name, :working_directory),
         {:ok, sha} <- sha(input.sha, directory, node_name) do
      payload =
        %{"state" => state, "context" => input.context}
        |> put_present("description", input.description)
        |> put_present("target_url", input.target_url)

      repo.owner
      |> GithubCapabilities.create_commit_status(repo.repo, sha, payload, directory)
      |> status(sha, input.context, node_name)
    end
  end

  @spec validated_state(state :: String.t(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp validated_state(state, node_name) do
    allowed = CommitStatusType.states()

    if state in allowed,
      do: {:ok, state},
      else: {:error, GithubError.invalid_commit_status_state(state, allowed, node_name, :state)}
  end

  @spec sha(sha :: String.t() | nil, directory :: String.t(), node_name :: Node.name()) ::
          {:ok, String.t()} | {:error, Error.t()}
  defp sha(sha, _directory, _node_name) when is_binary(sha), do: {:ok, sha}
  defp sha(nil, directory, node_name), do: GithubCapabilities.head_sha(directory, node_name, :sha)

  @spec put_present(payload :: map(), key :: String.t(), value :: String.t() | nil) :: map()
  defp put_present(payload, key, value) when is_binary(value), do: Map.put(payload, key, value)
  defp put_present(payload, _key, nil), do: payload

  @spec status(
          result :: GithubCapabilities.result(),
          sha :: String.t(),
          context :: String.t(),
          node_name :: Node.name()
        ) :: {:ok, map()} | {:error, Error.t()}
  defp status({:ok, %{"state" => state} = answer}, sha, context, _node_name)
       when is_binary(state),
       do:
         {:ok,
          %{
            sha: sha,
            state: state,
            context: answer["context"] || context,
            url: answer["target_url"]
          }}

  defp status({:ok, body}, _sha, _context, node_name),
    do: {:error, GithubError.request_failed(inspect(body), node_name, :state)}

  defp status({:error, failure}, _sha, _context, node_name),
    do: {:error, GithubError.request_failed(failure, node_name, :state)}
end
