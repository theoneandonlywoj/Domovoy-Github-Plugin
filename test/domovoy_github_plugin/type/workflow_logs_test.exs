defmodule DomovoyGithubPlugin.Type.WorkflowLogsTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.WorkflowLogs, as: WorkflowLogsType

  doctest WorkflowLogsType

  describe "cast/2" do
    test "wraps an archive, and rejects a negative size or a missing path" do
      assert {:ok, _} = WorkflowLogsType.cast(%{run_id: 1, path: "/x.zip", bytes: 0}, %{})
      assert :error = WorkflowLogsType.cast(%{run_id: 1, path: "/x.zip", bytes: -1}, %{})
      assert :error = WorkflowLogsType.cast(%{run_id: 1, bytes: 1}, %{})
    end
  end
end
