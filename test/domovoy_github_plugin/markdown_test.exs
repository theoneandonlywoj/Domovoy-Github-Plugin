defmodule DomovoyGithubPlugin.MarkdownTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Markdown

  doctest Markdown

  describe "render/1" do
    test "renders every block type from atom keys and from string keys" do
      blocks = [
        %{type: "paragraph", text: "p"},
        %{"type" => "heading", "text" => "h", "level" => 1},
        %{type: "quote", text: "q"},
        %{type: "code_block", code: "c"},
        %{type: "details", summary: "s", body: "b"},
        %{type: "table", headers: ["a"], rows: [["1"]]},
        %{type: "checklist", items: ["x", %{text: "y", done: true}]},
        %{type: "link", text: "t", url: "u"},
        %{"type" => "mention", "login" => "octocat"}
      ]

      assert {:ok, text} = Markdown.render(blocks)

      assert text ==
               Enum.join(
                 [
                   "p",
                   "# h",
                   "> q",
                   "```\nc\n```",
                   "<details>\n<summary>s</summary>\n\nb\n\n</details>",
                   "| a |\n| --- |\n| 1 |",
                   "- [ ] x\n- [x] y",
                   "[t](u)",
                   "@octocat"
                 ],
                 "\n\n"
               )
    end

    test "rejects a block with a field of the wrong shape" do
      assert :error = Markdown.render([%{type: "quote", text: 1}])
      assert :error = Markdown.render([%{type: "table", headers: "a", rows: []}])
      assert :error = Markdown.render([%{type: "checklist", items: [1]}])
      assert :error = Markdown.render([%{type: "link", text: "t"}])
      assert :error = Markdown.render([%{type: "code_block", code: "c", language: 1}])
      assert :error = Markdown.render([%{type: "details", summary: "s"}])
      assert :error = Markdown.render([%{text: "no type"}])
      assert :error = Markdown.render([1])
      assert :error = Markdown.render("not a list")
    end
  end

  describe "table/2" do
    test "escapes pipes in cells" do
      assert Markdown.table(["a|b"], [["c|d"]]) == "| a\\|b |\n| --- |\n| c\\|d |"
    end
  end

  describe "join/1" do
    test "drops empty blocks and keeps the order" do
      assert Markdown.join(["", "a", "", "b", ""]) == "a\n\nb"
      assert Markdown.join([]) == ""
    end
  end
end
