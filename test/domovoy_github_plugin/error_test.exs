defmodule DomovoyGithubPlugin.ErrorTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Error
  alias DomovoyGithubPlugin.Error, as: GithubError

  require GithubError

  doctest GithubError

  @plugin_directory Path.expand("../../lib/domovoy_github_plugin", __DIR__)

  @node_name "get_pr"
  @field_name :state

  describe "types/0" do
    test "names every type that this module builds" do
      assert GithubError.types() == [
               :github_request_failed,
               :github_origin_not_parsed,
               :github_invalid_pull_request_state,
               :github_config_not_found,
               :github_create_or_update_pr_failed
             ]
    end

    test "each builder gives a type that types/0 names" do
      assert Enum.map(built(), & &1.type) == GithubError.types()
      assert Enum.all?(built(), &match?(%Error{}, &1))
    end

    test "every error names the node and the field" do
      assert Enum.all?(built(), &(&1.metadata.node_name == @node_name))
      assert Enum.all?(built(), &(&1.metadata.field_name == @field_name))
    end

    test "no error carries a node, a node input, or a resolved value" do
      for error <- built() do
        refute Map.has_key?(error.metadata, :node)
        refute Map.has_key?(error.metadata, :node_input)
        refute Map.has_key?(error.metadata, :value)
      end
    end
  end

  describe "is_type/1" do
    test "accepts each type this module builds" do
      assert Enum.all?(GithubError.types(), fn type -> GithubError.is_type(type) end)
    end

    test "rejects a type of another plugin" do
      refute GithubError.is_type(:git_command_failed)
      refute GithubError.is_type("github_request_failed")
    end
  end

  describe "the plugin builds each error here" do
    test "no other module of the GitHub plugin calls DomovoyCore.Error.new/1" do
      sources =
        @plugin_directory
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.reject(&(Path.basename(&1) == "error.ex"))

      assert sources != [], "no sources found under " <> @plugin_directory

      offenders =
        sources
        |> Enum.filter(&(&1 |> File.read!() |> String.contains?("Error.new(%{")))
        |> Enum.map(&Path.relative_to(&1, @plugin_directory))

      assert offenders == [],
             "these modules build errors outside DomovoyGithubPlugin.Error: " <>
               Enum.join(offenders, ", ")
    end

    test "no module of the GitHub plugin reads a node input" do
      offenders =
        @plugin_directory
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.filter(&(&1 |> File.read!() |> String.contains?("node_input")))
        |> Enum.map(&Path.relative_to(&1, @plugin_directory))

      assert offenders == [],
             "these modules still name a node input: " <> Enum.join(offenders, ", ")
    end
  end

  describe "create_or_update_pr_failed/3" do
    test "carries the reason of the failure" do
      assert %Error{type: type, reason: reason} =
               GithubError.create_or_update_pr_failed(
                 "Validation Failed",
                 @node_name,
                 @field_name
               )

      assert type == :github_create_or_update_pr_failed
      assert reason == "Validation Failed"
    end
  end

  @spec built() :: [Error.t()]
  defp built do
    [
      GithubError.request_failed("Bad credentials", @node_name, @field_name),
      GithubError.origin_not_parsed("git@gitlab.com:owner/repo.git", @node_name, @field_name),
      GithubError.invalid_pull_request_state("merged", ["open"], @node_name, @field_name),
      GithubError.config_not_found(
        "/repo/.domovoy/config/github.json",
        @node_name,
        @field_name
      ),
      GithubError.create_or_update_pr_failed("Validation Failed", @node_name, @field_name)
    ]
  end
end
