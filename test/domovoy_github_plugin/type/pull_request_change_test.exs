defmodule DomovoyGithubPlugin.Type.PullRequestChangeTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.PullRequestChange, as: PullRequestChangeType

  describe "cast/2" do
    test "wraps a created and an updated change" do
      created = %{action: "created", number: 7, url: "https://github.com/pr/7"}
      updated = %{created | action: "updated"}

      assert {:ok, ^created} = PullRequestChangeType.cast(created, %{})

      assert {:ok, ^updated} = PullRequestChangeType.cast(updated, %{})
    end

    test "rejects an action that is neither created nor updated" do
      assert :error = PullRequestChangeType.cast(%{action: "deleted", number: 7, url: "u"}, %{})
    end

    test "rejects a non-integer number and a map missing a key" do
      assert :error = PullRequestChangeType.cast(%{action: "created", number: "7", url: "u"}, %{})

      assert :error = PullRequestChangeType.cast(%{action: "created"}, %{})
    end
  end

  describe "dump/1" do
    test "returns the change" do
      state = %{action: "created", number: 7, url: "u"}

      assert {:ok, document} = PullRequestChangeType.dump(state)
      assert PullRequestChangeType.load(document) == {:ok, state}
    end
  end
end
