defmodule DomovoyGithubPlugin.Runner.ReadConfigTest do
  use ExUnit.Case, async: true

  alias DomovoyCore.Error
  alias DomovoyCore.Node
  alias DomovoyCore.Type.Directory, as: DirectoryType
  alias DomovoyCore.Type.Integer, as: IntegerType
  alias DomovoyCore.Type.String, as: StringType
  alias DomovoyCore.Value
  alias DomovoyGithubPlugin.Capabilities
  alias DomovoyGithubPlugin.Runner.ReadConfig
  alias DomovoyGithubPlugin.Test.NodeRunner
  alias DomovoyGithubPlugin.Type.Config, as: ConfigType

  describe "run/2" do
    test "loads the config discovered from the working directory" do
      root = write_config!(~s({"access_token":"token","default_base_branch":"main"}))

      node = build_node(%{working_directory: {root, DirectoryType}})

      assert %Value{value: config, type: ConfigType} = NodeRunner.run(node, [])
      assert config["access_token"] == "token"
      assert config["default_base_branch"] == "main"
    end

    test "loads the config from a path named by a dependency" do
      root = write_config!(~s({"access_token":"token"}))
      path = Path.join(root, Capabilities.config_relative_path())

      node = build_node(%{}, %{config_path: {"path", StringType}})
      config_path = Value.cast!(path, StringType)

      assert %Value{value: %{"access_token" => "token"}} =
               NodeRunner.run(node, [{"path", config_path}])
    end

    test "uses a config argument" do
      node = build_node(%{config: {%{"access_token" => "inline"}, ConfigType}})

      assert %Value{value: %{"access_token" => "inline"}} = NodeRunner.run(node, [])
    end

    test "returns a contextual error when the file is missing" do
      root = Path.join(System.tmp_dir!(), "domovoy-gh-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf(root) end)

      node = build_node(%{working_directory: {root, DirectoryType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :github_config_not_found
    end

    test "returns a cast error naming the path when the token is blank" do
      root = write_config!(~s({"access_token":"  "}))

      node = build_node(%{working_directory: {root, DirectoryType}})

      assert %Error{} = error = NodeRunner.run(node, [])
      assert error.type == :cast_error
      assert error.metadata[:path] =~ "github.json"
    end

    test "returns a contextual error when the named input is not a string" do
      node = build_node(%{}, %{config_path: {"path", StringType}})
      config_path = Value.cast!(1, IntegerType)

      assert %Error{} = error = NodeRunner.run(node, [{"path", config_path}])
      assert error.type == :binding_cast_failed
      assert error.reason.field == :config_path
    end
  end

  @spec build_node(args :: map(), bind :: map()) :: Node.t()
  defp build_node(args, bind \\ %{}) do
    Node.new(%{
      name: "read_github_config",
      runner: ReadConfig,
      type: ConfigType,
      args: args,
      bind: bind
    })
  end

  @spec write_config!(String.t()) :: String.t()
  defp write_config!(contents) do
    root = Path.join(System.tmp_dir!(), "domovoy-gh-#{System.unique_integer([:positive])}")
    path = Path.join(root, Capabilities.config_relative_path())

    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    on_exit(fn -> File.rm_rf(root) end)

    root
  end
end
