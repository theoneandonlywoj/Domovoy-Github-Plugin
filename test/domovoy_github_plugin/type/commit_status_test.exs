defmodule DomovoyGithubPlugin.Type.CommitStatusTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.CommitStatus, as: CommitStatusType

  doctest CommitStatusType

  describe "cast/2" do
    test "wraps each state GitHub accepts" do
      for state <- CommitStatusType.states() do
        status = %{sha: "abc", state: state, context: "domovoy", url: nil}
        assert {:ok, ^status} = CommitStatusType.cast(status, %{})
      end
    end

    test "rejects a state GitHub does not accept and a missing key" do
      assert :error =
               CommitStatusType.cast(%{sha: "abc", state: "done", context: "c", url: nil}, %{})

      assert :error = CommitStatusType.cast(%{sha: "abc"}, %{})
    end
  end
end
