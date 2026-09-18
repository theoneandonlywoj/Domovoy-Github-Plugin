defmodule DomovoyGithubPlugin.Type.WorkflowJobsTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.WorkflowJobs, as: WorkflowJobsType

  doctest WorkflowJobsType

  @job %{
    id: 1,
    name: "test",
    status: "completed",
    conclusion: "failure",
    url: "u",
    steps: [%{number: 1, name: "mix test", status: "completed", conclusion: "failure"}]
  }

  describe "cast/2" do
    test "wraps jobs with and without steps" do
      assert {:ok, [@job]} = WorkflowJobsType.cast([@job], %{})
      assert {:ok, _} = WorkflowJobsType.cast([%{@job | steps: []}], %{})
    end

    test "rejects a malformed step and a malformed job" do
      assert :error = WorkflowJobsType.cast([%{@job | steps: [%{number: "1"}]}], %{})
      assert :error = WorkflowJobsType.cast([%{@job | id: nil}], %{})
      assert :error = WorkflowJobsType.cast(@job, %{})
    end
  end

  describe "load/1" do
    test "rejects a job without steps in the document" do
      assert :error = WorkflowJobsType.load([%{"id" => 1, "name" => "x"}])
    end
  end
end
