defmodule DomovoyGithubPlugin.Error do
  @moduledoc """
  Builds the errors of the GitHub plugin with safe execution context.

  Each error keeps `node_name` and `field_name` in its metadata. An error never
  keeps a node, an input struct, a configuration map, or a resolved value.

  ## Examples

      iex> DomovoyGithubPlugin.Error.request_failed("Bad credentials", "get_pr", :state)
      %DomovoyCore.Error{
        type: :github_request_failed,
        reason: "Bad credentials",
        metadata: %{node_name: "get_pr", field_name: :state}
      }
  """

  alias DomovoyCore.Node

  @types [
    :github_request_failed,
    :github_origin_not_parsed,
    :github_invalid_pull_request_state,
    :github_config_not_found,
    :github_create_or_update_pr_failed
  ]

  @typedoc "The `type` of an error that this module builds."
  @type type() ::
          :github_request_failed
          | :github_origin_not_parsed
          | :github_invalid_pull_request_state
          | :github_config_not_found
          | :github_create_or_update_pr_failed

  @typedoc "The name of the input field that an error concerns."
  @type field_name() :: atom()

  @doc """
  Returns `true` if `value` is a type that this module builds.

  ## Examples

      iex> require DomovoyGithubPlugin.Error
      iex> DomovoyGithubPlugin.Error.is_type(:github_request_failed)
      true
  """
  defguard is_type(value) when value in @types

  @doc """
  Returns every error type that this module builds.

  ## Examples

      iex> :github_request_failed in DomovoyGithubPlugin.Error.types()
      true

      iex> length(DomovoyGithubPlugin.Error.types())
      5
  """
  @spec types() :: [type()]
  def types, do: @types

  @doc """
  Builds an error for a request that GitHub rejected.

  ## Examples

      iex> DomovoyGithubPlugin.Error.request_failed("Bad credentials", "get_pr", :state)
      %DomovoyCore.Error{
        type: :github_request_failed,
        reason: "Bad credentials",
        metadata: %{node_name: "get_pr", field_name: :state}
      }
  """
  @spec request_failed(
          reason :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def request_failed(reason, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_request_failed,
      reason: reason,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for an `origin` that does not name a GitHub repository.

  ## Examples

      iex> DomovoyGithubPlugin.Error.origin_not_parsed("git@gitlab.com:o/r.git", "get_pr", :working_directory)
      %DomovoyCore.Error{
        type: :github_origin_not_parsed,
        metadata: %{
          remote_url: "git@gitlab.com:o/r.git",
          node_name: "get_pr",
          field_name: :working_directory
        }
      }
  """
  @spec origin_not_parsed(
          remote_url :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def origin_not_parsed(remote_url, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_origin_not_parsed,
      metadata: %{remote_url: remote_url, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a pull request state filter that GitHub does not accept.

  ## Examples

      iex> DomovoyGithubPlugin.Error.invalid_pull_request_state("merged", ["open", "all"], "get_pr", :state)
      %DomovoyCore.Error{
        type: :github_invalid_pull_request_state,
        metadata: %{
          state: "merged",
          allowed_states: ["open", "all"],
          node_name: "get_pr",
          field_name: :state
        }
      }
  """
  @spec invalid_pull_request_state(
          state :: String.t(),
          allowed_states :: [String.t()],
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def invalid_pull_request_state(state, allowed_states, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_invalid_pull_request_state,
      metadata: %{
        state: state,
        allowed_states: allowed_states,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds an error for a GitHub configuration file that cannot be loaded.

  ## Examples

      iex> DomovoyGithubPlugin.Error.config_not_found("/repo/github.json", "read_config", :config_path)
      %DomovoyCore.Error{
        type: :github_config_not_found,
        metadata: %{
          path: "/repo/github.json",
          node_name: "read_config",
          field_name: :config_path
        }
      }
  """
  @spec config_not_found(
          path :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def config_not_found(path, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_config_not_found,
      metadata: %{path: path, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a pull request that Domovoy could not open or change.

  ## Examples

      iex> DomovoyGithubPlugin.Error.create_or_update_pr_failed("base branch missing", "create_pr", :base_branch)
      %DomovoyCore.Error{
        type: :github_create_or_update_pr_failed,
        reason: "base branch missing",
        metadata: %{node_name: "create_pr", field_name: :base_branch}
      }
  """
  @spec create_or_update_pr_failed(
          reason :: term(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def create_or_update_pr_failed(reason, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_create_or_update_pr_failed,
      reason: reason,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end
end
