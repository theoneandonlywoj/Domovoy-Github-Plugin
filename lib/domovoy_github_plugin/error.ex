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
  alias DomovoyGithubPlugin.Capabilities

  @types [
    :github_request_failed,
    :github_origin_not_parsed,
    :github_invalid_pull_request_state,
    :github_config_not_found,
    :github_create_or_update_pr_failed,
    :github_pull_request_not_found,
    :github_graphql_failed,
    :github_invalid_merge_method,
    :github_pull_request_not_mergeable,
    :github_stack_cycle_detected,
    :github_invalid_review_event,
    :github_invalid_commit_status_state,
    :github_workflow_run_not_found,
    :github_workflow_run_timed_out,
    :github_workflow_logs_write_failed,
    :github_issue_not_found,
    :github_label_not_found,
    :github_release_not_found,
    :github_branch_not_found
  ]

  @typedoc "The `type` of an error that this module builds."
  @type type() ::
          :github_request_failed
          | :github_origin_not_parsed
          | :github_invalid_pull_request_state
          | :github_config_not_found
          | :github_create_or_update_pr_failed
          | :github_pull_request_not_found
          | :github_graphql_failed
          | :github_invalid_merge_method
          | :github_pull_request_not_mergeable
          | :github_stack_cycle_detected
          | :github_invalid_review_event
          | :github_invalid_commit_status_state
          | :github_workflow_run_not_found
          | :github_workflow_run_timed_out
          | :github_workflow_logs_write_failed
          | :github_issue_not_found
          | :github_label_not_found
          | :github_release_not_found
          | :github_branch_not_found

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
      19
  """
  @spec types() :: [type()]
  def types, do: @types

  @doc """
  Builds an error for a request that GitHub rejected.

  A failure from `DomovoyGithubPlugin.Capabilities` keeps its HTTP status in
  the metadata. A plain reason has no status.

  ## Examples

      iex> DomovoyGithubPlugin.Error.request_failed("Bad credentials", "get_pr", :state)
      %DomovoyCore.Error{
        type: :github_request_failed,
        reason: "Bad credentials",
        metadata: %{node_name: "get_pr", field_name: :state}
      }

      iex> DomovoyGithubPlugin.Error.request_failed(
      ...>   %{status: 401, message: "Bad credentials"},
      ...>   "get_pr",
      ...>   :state
      ...> )
      %DomovoyCore.Error{
        type: :github_request_failed,
        reason: "Bad credentials",
        metadata: %{status: 401, node_name: "get_pr", field_name: :state}
      }
  """
  @spec request_failed(
          reason :: String.t() | Capabilities.failure(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def request_failed(%{status: status, message: message}, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_request_failed,
      reason: message,
      metadata: %{status: status, node_name: node_name, field_name: field_name}
    })
  end

  def request_failed(reason, node_name, field_name) when is_binary(reason) do
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

  @doc """
  Builds an error for a pull request that a runner needs and GitHub does not
  have.

  `number` is the number the runner asked for, or `nil` when the runner asked
  for the open pull request of a branch. `head` is that branch as
  `owner:branch`, or `nil` when the runner asked for a number.

  ## Examples

      iex> DomovoyGithubPlugin.Error.pull_request_not_found(nil, "owner:feature", "merge_pr", :number)
      %DomovoyCore.Error{
        type: :github_pull_request_not_found,
        metadata: %{
          number: nil,
          head: "owner:feature",
          node_name: "merge_pr",
          field_name: :number
        }
      }
  """
  @spec pull_request_not_found(
          number :: pos_integer() | nil,
          head :: String.t() | nil,
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def pull_request_not_found(number, head, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_pull_request_not_found,
      metadata: %{number: number, head: head, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a GraphQL query that GitHub rejected.

  ## Examples

      iex> DomovoyGithubPlugin.Error.graphql_failed("Could not resolve to a node", "resolve_thread", :thread_id)
      %DomovoyCore.Error{
        type: :github_graphql_failed,
        reason: "Could not resolve to a node",
        metadata: %{node_name: "resolve_thread", field_name: :thread_id}
      }
  """
  @spec graphql_failed(
          reason :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def graphql_failed(reason, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_graphql_failed,
      reason: reason,
      metadata: %{node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a merge method that GitHub does not accept.

  ## Examples

      iex> DomovoyGithubPlugin.Error.invalid_merge_method("fast-forward", ["merge", "squash", "rebase"], "merge_pr", :merge_method)
      %DomovoyCore.Error{
        type: :github_invalid_merge_method,
        metadata: %{
          merge_method: "fast-forward",
          allowed_merge_methods: ["merge", "squash", "rebase"],
          node_name: "merge_pr",
          field_name: :merge_method
        }
      }
  """
  @spec invalid_merge_method(
          merge_method :: String.t(),
          allowed_merge_methods :: [String.t()],
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def invalid_merge_method(merge_method, allowed_merge_methods, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_invalid_merge_method,
      metadata: %{
        merge_method: merge_method,
        allowed_merge_methods: allowed_merge_methods,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds an error for a pull request that GitHub refuses to merge.

  GitHub refuses a merge when a check fails, a review is missing, the branch
  has a conflict, or the head moved since the caller read it.

  ## Examples

      iex> DomovoyGithubPlugin.Error.pull_request_not_mergeable(42, "Pull Request is not mergeable", "merge_pr", :number)
      %DomovoyCore.Error{
        type: :github_pull_request_not_mergeable,
        reason: "Pull Request is not mergeable",
        metadata: %{number: 42, node_name: "merge_pr", field_name: :number}
      }
  """
  @spec pull_request_not_mergeable(
          number :: pos_integer(),
          reason :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def pull_request_not_mergeable(number, reason, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_pull_request_not_mergeable,
      reason: reason,
      metadata: %{number: number, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a stack of pull requests whose base branches loop, or
  whose depth passes the limit of the walk.

  `branches` lists the head branches the walk visited, in order.

  ## Examples

      iex> DomovoyGithubPlugin.Error.stack_cycle_detected(["a", "b", "a"], "get_pr_stack", :number)
      %DomovoyCore.Error{
        type: :github_stack_cycle_detected,
        metadata: %{branches: ["a", "b", "a"], node_name: "get_pr_stack", field_name: :number}
      }
  """
  @spec stack_cycle_detected(
          branches :: [String.t()],
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def stack_cycle_detected(branches, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_stack_cycle_detected,
      metadata: %{branches: branches, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a review event that GitHub does not accept.

  ## Examples

      iex> DomovoyGithubPlugin.Error.invalid_review_event("merge", ["approve", "comment"], "review_pr", :event)
      %DomovoyCore.Error{
        type: :github_invalid_review_event,
        metadata: %{
          event: "merge",
          allowed_events: ["approve", "comment"],
          node_name: "review_pr",
          field_name: :event
        }
      }
  """
  @spec invalid_review_event(
          event :: String.t(),
          allowed_events :: [String.t()],
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def invalid_review_event(event, allowed_events, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_invalid_review_event,
      metadata: %{
        event: event,
        allowed_events: allowed_events,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds an error for a commit status state that GitHub does not accept.

  ## Examples

      iex> DomovoyGithubPlugin.Error.invalid_commit_status_state("done", ["success"], "set_status", :state)
      %DomovoyCore.Error{
        type: :github_invalid_commit_status_state,
        metadata: %{
          state: "done",
          allowed_states: ["success"],
          node_name: "set_status",
          field_name: :state
        }
      }
  """
  @spec invalid_commit_status_state(
          state :: String.t(),
          allowed_states :: [String.t()],
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def invalid_commit_status_state(state, allowed_states, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_invalid_commit_status_state,
      metadata: %{
        state: state,
        allowed_states: allowed_states,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds an error for a branch that has no workflow run, or none of the
  workflow the runner asked for.

  ## Examples

      iex> DomovoyGithubPlugin.Error.workflow_run_not_found("feature", "ci.yml", "get_run", :workflow)
      %DomovoyCore.Error{
        type: :github_workflow_run_not_found,
        metadata: %{branch: "feature", workflow: "ci.yml", node_name: "get_run", field_name: :workflow}
      }
  """
  @spec workflow_run_not_found(
          branch :: String.t(),
          workflow :: String.t() | nil,
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def workflow_run_not_found(branch, workflow, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_workflow_run_not_found,
      metadata: %{
        branch: branch,
        workflow: workflow,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds an error for a workflow run that did not finish within the time the
  runner waited.

  ## Examples

      iex> DomovoyGithubPlugin.Error.workflow_run_timed_out(123, 60_000, "wait_for_run", :timeout_ms)
      %DomovoyCore.Error{
        type: :github_workflow_run_timed_out,
        metadata: %{run_id: 123, timeout_ms: 60_000, node_name: "wait_for_run", field_name: :timeout_ms}
      }
  """
  @spec workflow_run_timed_out(
          run_id :: pos_integer(),
          timeout_ms :: non_neg_integer(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def workflow_run_timed_out(run_id, timeout_ms, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_workflow_run_timed_out,
      metadata: %{
        run_id: run_id,
        timeout_ms: timeout_ms,
        node_name: node_name,
        field_name: field_name
      }
    })
  end

  @doc """
  Builds an error for a logs archive that the runner could not write to disk.

  ## Examples

      iex> DomovoyGithubPlugin.Error.workflow_logs_write_failed("/x/logs.zip", :eacces, "get_logs", :destination)
      %DomovoyCore.Error{
        type: :github_workflow_logs_write_failed,
        reason: :eacces,
        metadata: %{path: "/x/logs.zip", node_name: "get_logs", field_name: :destination}
      }
  """
  @spec workflow_logs_write_failed(
          path :: String.t(),
          reason :: atom(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def workflow_logs_write_failed(path, reason, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_workflow_logs_write_failed,
      reason: reason,
      metadata: %{path: path, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for an issue number that names nothing.

  ## Examples

      iex> DomovoyGithubPlugin.Error.issue_not_found(99, "get_issue", :number)
      %DomovoyCore.Error{
        type: :github_issue_not_found,
        metadata: %{number: 99, node_name: "get_issue", field_name: :number}
      }
  """
  @spec issue_not_found(
          number :: pos_integer(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def issue_not_found(number, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_issue_not_found,
      metadata: %{number: number, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a label that a pull request or issue does not have.

  ## Examples

      iex> DomovoyGithubPlugin.Error.label_not_found("wip", 42, "remove_label", :label)
      %DomovoyCore.Error{
        type: :github_label_not_found,
        metadata: %{label: "wip", number: 42, node_name: "remove_label", field_name: :label}
      }
  """
  @spec label_not_found(
          label :: String.t(),
          number :: pos_integer(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def label_not_found(label, number, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_label_not_found,
      metadata: %{label: label, number: number, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a release that the repository does not have.

  `tag` is the tag the runner asked for, or `nil` when it asked for the
  latest release.

  ## Examples

      iex> DomovoyGithubPlugin.Error.release_not_found("v9.0.0", "get_release", :tag)
      %DomovoyCore.Error{
        type: :github_release_not_found,
        metadata: %{tag: "v9.0.0", node_name: "get_release", field_name: :tag}
      }
  """
  @spec release_not_found(
          tag :: String.t() | nil,
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def release_not_found(tag, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_release_not_found,
      metadata: %{tag: tag, node_name: node_name, field_name: field_name}
    })
  end

  @doc """
  Builds an error for a branch that GitHub does not have.

  ## Examples

      iex> DomovoyGithubPlugin.Error.branch_not_found("gone", "get_branch", :branch)
      %DomovoyCore.Error{
        type: :github_branch_not_found,
        metadata: %{branch: "gone", node_name: "get_branch", field_name: :branch}
      }
  """
  @spec branch_not_found(
          branch :: String.t(),
          node_name :: Node.name(),
          field_name :: field_name()
        ) :: DomovoyCore.Error.t()
  def branch_not_found(branch, node_name, field_name) do
    DomovoyCore.Error.new(%{
      type: :github_branch_not_found,
      metadata: %{branch: branch, node_name: node_name, field_name: field_name}
    })
  end
end
