defmodule DomovoyGithubPlugin.Type.ReleaseTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Release, as: ReleaseType

  doctest ReleaseType

  @release %{id: 1, tag_name: "v1", name: nil, body: "", draft: false, prerelease: true, url: nil}

  describe "cast/2" do
    test "wraps a release and rejects a non-boolean flag or a missing key" do
      assert {:ok, @release} = ReleaseType.cast(@release, %{})
      assert :error = ReleaseType.cast(%{@release | draft: "no"}, %{})
      assert :error = ReleaseType.cast(Map.delete(@release, :prerelease), %{})
      assert :error = ReleaseType.cast(%{@release | tag_name: nil}, %{})
    end
  end
end
