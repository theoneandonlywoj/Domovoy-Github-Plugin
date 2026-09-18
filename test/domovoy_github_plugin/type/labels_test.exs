defmodule DomovoyGithubPlugin.Type.LabelsTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Labels, as: LabelsType

  doctest LabelsType

  describe "cast/2" do
    test "wraps a list of names and rejects a blank one" do
      assert {:ok, ["bug"]} = LabelsType.cast(["bug"], %{})
      assert {:ok, []} = LabelsType.cast([], %{})
      assert :error = LabelsType.cast([" "], %{})
      assert :error = LabelsType.cast("bug", %{})
    end
  end
end
