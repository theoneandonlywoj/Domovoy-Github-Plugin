defmodule DomovoyGithubPlugin.Type.WorkflowRunTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.WorkflowRun, as: WorkflowRunType

  require WorkflowRunType

  doctest WorkflowRunType

  @run %{id: 1, name: "CI", status: :completed, conclusion: :success, url: "u", head_sha: "abc"}

  describe "parse_status/1 and parse_conclusion/1" do
    test "read each word of GitHub" do
      for status <- WorkflowRunType.statuses() do
        assert WorkflowRunType.parse_status(Atom.to_string(status)) == status
      end

      for conclusion <- WorkflowRunType.conclusions() do
        assert WorkflowRunType.parse_conclusion(Atom.to_string(conclusion)) == conclusion
      end

      assert WorkflowRunType.parse_status(nil) == :invalid_state
      assert WorkflowRunType.parse_conclusion("") == :invalid_state
    end
  end

  describe "cast/2" do
    test "wraps a run that is going and a run that finished" do
      going = %{@run | status: :in_progress, conclusion: nil}

      assert {:ok, @run} = WorkflowRunType.cast(@run, %{})
      assert {:ok, ^going} = WorkflowRunType.cast(going, %{})
    end

    test "rejects a text status, a text conclusion, and a missing key" do
      assert :error = WorkflowRunType.cast(%{@run | status: "completed"}, %{})
      assert :error = WorkflowRunType.cast(%{@run | conclusion: "success"}, %{})
      assert :error = WorkflowRunType.cast(%{id: 1}, %{})
    end
  end

  describe "load/1" do
    test "reads nil and text conclusions, and rejects unknown words" do
      {:ok, document} = WorkflowRunType.dump(%{@run | status: :queued, conclusion: nil})
      assert {:ok, %{status: :queued, conclusion: nil}} = WorkflowRunType.load(document)

      {:ok, document} = WorkflowRunType.dump(@run)
      assert :error = WorkflowRunType.load(%{document | "status" => "flying"})
      assert :error = WorkflowRunType.load(%{document | "conclusion" => "exploded"})
    end
  end
end
