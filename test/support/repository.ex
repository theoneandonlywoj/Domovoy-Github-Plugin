defmodule DomovoyGithubPlugin.Test.Repository do
  @moduledoc """
  Builds throwaway Git repositories for tests that exercise real Git commands.

  Git capabilities are tested against actual repositories in `System.tmp_dir!/0`.
  Each repository is created under its own uniquely named parent directory so a
  test can clean up with `File.rm_rf(repository.parent)` in `on_exit/1`.

  ## Examples

  ```elixir
  repository = DomovoyGithubPlugin.Test.Repository.create!()
  on_exit(fn -> File.rm_rf(repository.parent) end)
  ```
  """

  @typedoc "A created repository and the directories it occupies."
  @type t() :: %{
          parent: String.t(),
          root: String.t(),
          remote: String.t() | nil
        }

  @doc """
  Creates a Git repository with one commit on `main` and returns its paths.

  `root` is the canonical path reported by `git rev-parse --show-toplevel`, so
  it compares equal to what capabilities return on platforms where the temporary
  directory is a symlink.

  ## Options

    * `:remote?` - also initialise a bare repository next to it, add it as
      `origin`, and push `main` with upstream tracking. Defaults to `true`.
    * `:subdirectories` - relative directories to create inside the working
      tree before the initial commit. Defaults to `[]`.

  ## Equivalent Bash

      git init --bare <parent>/origin.git
      git init --initial-branch=main <parent>/source
      git -C <root> commit -m "Initial commit"
      git -C <root> push -u origin main
  """
  @spec create!(keyword()) :: t()
  def create!(opts \\ []) do
    remote? = Keyword.get(opts, :remote?, true)
    subdirectories = Keyword.get(opts, :subdirectories, [])

    parent = Path.join(System.tmp_dir!(), "domovoy-github-#{unique_suffix()}")
    root = Path.join(parent, "source")
    remote = Path.join(parent, "origin.git")

    File.mkdir_p!(root)
    Enum.each(subdirectories, fn directory -> File.mkdir_p!(Path.join(root, directory)) end)

    if remote?, do: git!(["init", "--bare", remote])

    git!(["init", "--initial-branch=main", root])
    git!(["-C", root, "config", "user.email", "test@example.com"])
    git!(["-C", root, "config", "user.name", "Domovoy Test"])
    File.write!(Path.join(root, "README.md"), "test\n")
    git!(["-C", root, "add", "README.md"])
    git!(["-C", root, "commit", "-m", "Initial commit"])

    if remote? do
      git!(["-C", root, "remote", "add", "origin", remote])
      git!(["-C", root, "push", "-u", "origin", "main"])
    end

    %{
      parent: parent,
      root: root |> canonical_root() |> String.trim(),
      remote: if(remote?, do: remote)
    }
  end

  @doc """
  Runs a Git command, raising when it exits with a non-zero status.

  Returns the command's combined output so callers can assert on it.

  ## Equivalent Bash

      git <args...> 2>&1
  """
  @spec git!([String.t()]) :: String.t()
  def git!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, exit_status} ->
        raise "git #{Enum.join(args, " ")} exited with status #{exit_status}: #{output}"
    end
  end

  @spec canonical_root(String.t()) :: String.t()
  defp canonical_root(root), do: git!(["-C", root, "rev-parse", "--show-toplevel"])

  @spec unique_suffix() :: String.t()
  defp unique_suffix do
    8 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
