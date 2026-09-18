defmodule DomovoyGithubPlugin.Type.ComparisonTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Comparison, as: ComparisonType

  require ComparisonType

  doctest ComparisonType

  @comparison %{
    base: "main",
    head: "feat",
    status: :ahead,
    ahead_by: 1,
    behind_by: 0,
    total_commits: 1
  }

  describe "parse_status/1" do
    test "reads each word of GitHub" do
      for status <- [:ahead, :behind, :identical, :diverged] do
        assert ComparisonType.parse_status(Atom.to_string(status)) == status
      end

      assert ComparisonType.parse_status(nil) == :invalid_state
    end
  end

  describe "cast/2 and load/1" do
    test "wrap a comparison and reject a text status or a missing count" do
      assert {:ok, @comparison} = ComparisonType.cast(@comparison, %{})
      assert :error = ComparisonType.cast(%{@comparison | status: "ahead"}, %{})
      assert :error = ComparisonType.cast(Map.delete(@comparison, :behind_by), %{})
    end

    test "load rejects a status this type does not give" do
      {:ok, document} = ComparisonType.dump(@comparison)
      assert :error = ComparisonType.load(%{document | "status" => "sideways"})
      assert :error = ComparisonType.load(%{})
    end
  end
end
