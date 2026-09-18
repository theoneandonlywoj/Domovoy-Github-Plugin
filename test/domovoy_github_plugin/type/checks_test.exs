defmodule DomovoyGithubPlugin.Type.ChecksTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Checks, as: ChecksType

  require ChecksType

  doctest ChecksType

  @checks %{
    sha: "abc",
    state: :success,
    runs: [%{name: "test", status: "completed", conclusion: "success", url: nil}],
    statuses: [%{context: "ci", state: "success", url: nil}]
  }

  describe "cast/2" do
    test "wraps checks, and checks with nothing in them" do
      assert {:ok, @checks} = ChecksType.cast(@checks, %{})
      assert {:ok, _} = ChecksType.cast(%{@checks | state: :none, runs: [], statuses: []}, %{})
    end

    test "rejects a text state, a malformed run, and a malformed status" do
      assert :error = ChecksType.cast(%{@checks | state: "success"}, %{})
      assert :error = ChecksType.cast(%{@checks | runs: [%{name: 1}]}, %{})
      assert :error = ChecksType.cast(%{@checks | statuses: [%{context: nil}]}, %{})
    end
  end

  describe "load/1" do
    test "rejects a state this type does not give" do
      {:ok, document} = ChecksType.dump(@checks)
      assert :error = ChecksType.load(%{document | "state" => "done"})
      assert :error = ChecksType.load(%{})
    end
  end
end
