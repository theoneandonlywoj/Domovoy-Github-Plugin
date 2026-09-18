defmodule DomovoyGithubPlugin.Type.CommentBodyTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Type.CommentBody, as: CommentBodyType

  doctest CommentBodyType

  describe "cast/2" do
    test "keeps a string, including an empty one" do
      assert {:ok, "text"} = CommentBodyType.cast("text", %{})
      assert {:ok, ""} = CommentBodyType.cast("", %{})
    end

    test "renders a list of blocks into one string" do
      blocks = ["intro", %{type: "code_block", code: "x", language: "sh"}]

      assert {:ok, "intro\n\n```sh\nx\n```"} = CommentBodyType.cast(blocks, %{})
    end

    test "rejects a block it does not know and a non-text value" do
      assert :error = CommentBodyType.cast([%{type: "video"}], %{})
      assert :error = CommentBodyType.cast(%{type: "quote", text: "q"}, %{})
      assert :error = CommentBodyType.cast(nil, %{})
    end

    test "accepts the value of a String node, so a plain body binds into it" do
      %Value{value: text} = Value.cast!("from another node", StringType)

      assert {:ok, %Value{value: "from another node"}} = Value.cast(text, CommentBodyType)
    end
  end

  describe "dump/1 and load/1" do
    test "round-trip the string" do
      assert {:ok, "text"} = CommentBodyType.dump("text")
      assert {:ok, "text"} = CommentBodyType.load("text")
    end
  end
end
