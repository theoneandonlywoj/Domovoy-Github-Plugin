defmodule DomovoyGithubPlugin.Type.ReleaseNotesTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.ReleaseNotes, as: ReleaseNotesType

  doctest ReleaseNotesType

  describe "cast/2" do
    test "wraps notes and rejects a missing body" do
      assert {:ok, _} = ReleaseNotesType.cast(%{name: "v1", body: "notes"}, %{})
      assert :error = ReleaseNotesType.cast(%{name: "v1"}, %{})
      assert :error = ReleaseNotesType.cast(%{name: "v1", body: nil}, %{})
    end
  end
end
