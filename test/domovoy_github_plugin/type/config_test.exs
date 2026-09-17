defmodule DomovoyGithubPlugin.Type.ConfigTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.Config, as: ConfigType

  describe "cast/2" do
    test "wraps a config carrying an access token" do
      config = %{"access_token" => "token", "default_base_branch" => "main"}

      assert {:ok, ^config} = ConfigType.cast(config, %{})
    end

    test "accepts a config with only the access token, since the rest is optional" do
      assert {:ok, _} = ConfigType.cast(%{"access_token" => "token"}, %{})
    end

    test "rejects a blank, absent, or non-string access token" do
      assert :error = ConfigType.cast(%{"access_token" => "   "}, %{})
      assert :error = ConfigType.cast(%{"access_token" => ""}, %{})
      assert :error = ConfigType.cast(%{"access_token" => 1}, %{})
      assert :error = ConfigType.cast(%{"default_base_branch" => "main"}, %{})
    end

    test "rejects a value that is not a map" do
      assert :error = ConfigType.cast("token", %{})
    end
  end
end
