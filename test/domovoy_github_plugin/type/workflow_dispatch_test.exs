defmodule DomovoyGithubPlugin.Type.WorkflowDispatchTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.WorkflowDispatch, as: WorkflowDispatchType

  doctest WorkflowDispatchType

  describe "cast/2" do
    test "wraps a dispatch and rejects one that did not happen" do
      assert {:ok, _} =
               WorkflowDispatchType.cast(
                 %{workflow: "ci.yml", ref: "main", dispatched: true},
                 %{}
               )

      assert :error =
               WorkflowDispatchType.cast(
                 %{workflow: "ci.yml", ref: "main", dispatched: false},
                 %{}
               )

      assert :error = WorkflowDispatchType.cast(%{workflow: "ci.yml"}, %{})
    end
  end
end
