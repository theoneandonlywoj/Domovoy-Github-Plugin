defmodule DomovoyGithubPlugin.Type.ReviewThreadChangeTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.ReviewThreadChange, as: ReviewThreadChangeType

  doctest ReviewThreadChangeType

  describe "cast/2" do
    test "wraps a change and rejects a wrong field" do
      assert {:ok, _} = ReviewThreadChangeType.cast(%{id: "PRRT_1", resolved: true}, %{})
      assert :error = ReviewThreadChangeType.cast(%{id: 1, resolved: true}, %{})
      assert :error = ReviewThreadChangeType.cast(%{id: "PRRT_1"}, %{})
    end
  end
end
