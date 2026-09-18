defmodule DomovoyGithubPlugin.Type.AssigneesTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Assignees, as: AssigneesType

  doctest AssigneesType

  describe "cast/2" do
    test "wraps a list of logins and rejects a blank one" do
      assert {:ok, ["octocat"]} = AssigneesType.cast(["octocat"], %{})
      assert :error = AssigneesType.cast([""], %{})
      assert :error = AssigneesType.cast(nil, %{})
    end
  end
end
