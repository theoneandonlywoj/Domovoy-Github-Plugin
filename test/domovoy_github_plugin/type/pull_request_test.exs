defmodule DomovoyGithubPlugin.Type.PullRequestTest do
  use ExUnit.Case, async: true

  alias DomovoyGithubPlugin.Type.PullRequest, as: PullRequestType

  require PullRequestType

  doctest PullRequestType

  @merged_at "2026-09-09T18:26:21Z"

  describe "states/0" do
    test "names every state, and does not name nil" do
      assert PullRequestType.states() == [
               :open,
               :closed,
               :merged,
               :not_found,
               :invalid_state
             ]

      refute nil in PullRequestType.states()
    end
  end

  describe "is_state/1" do
    test "accepts each state this type names" do
      assert Enum.all?(
               PullRequestType.states(),
               fn state -> PullRequestType.is_state(state) end
             )
    end

    test "rejects nil and text" do
      refute PullRequestType.is_state(nil)
      refute PullRequestType.is_state("open")
    end
  end

  describe "parse_state/2" do
    test "reads an open pull request" do
      assert PullRequestType.parse_state("open", nil) == :open
    end

    test "reads a closed pull request without a timestamp as closed" do
      assert PullRequestType.parse_state("closed", nil) == :closed
    end

    test "reads a closed pull request with a timestamp as merged" do
      assert PullRequestType.parse_state("closed", @merged_at) == :merged
    end

    test "reads a state GitHub does not report as :invalid_state" do
      assert PullRequestType.parse_state("merged", nil) == :invalid_state
      assert PullRequestType.parse_state(nil, nil) == :invalid_state
      assert PullRequestType.parse_state(:open, nil) == :invalid_state
    end

    test "never gives :not_found, which comes from an empty search" do
      states =
        for raw_state <- ["open", "closed", "merged", nil],
            raw_merged_at <- [@merged_at, nil],
            do: PullRequestType.parse_state(raw_state, raw_merged_at)

      refute :not_found in states
    end
  end

  describe "cast/2" do
    test "wraps an open pull request" do
      state = %{
        state: :open,
        number: 7,
        title: "feat",
        body: "why",
        url: "https://github.com/pr/7"
      }

      assert {:ok, ^state} = PullRequestType.cast(state, %{})
    end

    test "wraps a merged pull request" do
      state = %{
        state: :merged,
        number: 7,
        title: "feat",
        body: "why",
        url: "https://github.com/pr/7"
      }

      assert {:ok, ^state} = PullRequestType.cast(state, %{})
    end

    test "wraps the not-found answer, which is a value rather than an error" do
      state = %{state: :not_found, number: nil, title: nil, body: nil, url: nil}

      assert {:ok, ^state} = PullRequestType.cast(state, %{})
    end

    test "wraps a state that did not match, which the runner reports as invalid" do
      state = %{
        state: :invalid_state,
        number: 7,
        title: "feat",
        body: "why",
        url: "https://github.com/pr/7"
      }

      assert {:ok, ^state} = PullRequestType.cast(state, %{})
    end

    test "rejects a state that is not an atom this type names" do
      base = %{state: :open, number: 7, title: nil, body: nil, url: nil}

      assert :error = PullRequestType.cast(%{base | state: nil}, %{})
      assert :error = PullRequestType.cast(%{base | state: :all}, %{})
      assert :error = PullRequestType.cast(%{base | state: "open"}, %{})
    end

    test "rejects a field that has the wrong type" do
      base = %{state: :open, number: 7, title: nil, body: nil, url: nil}

      assert :error = PullRequestType.cast(%{base | number: "7"}, %{})
      assert :error = PullRequestType.cast(%{base | title: :feat}, %{})
      assert :error = PullRequestType.cast(%{base | body: :why}, %{})
      assert :error = PullRequestType.cast(%{base | url: 7}, %{})
    end

    test "rejects a map missing a key and a non-map value" do
      assert :error = PullRequestType.cast(%{state: :open}, %{})
      assert :error = PullRequestType.cast(nil, %{})
    end
  end

  describe "open?/1, merged?/1, closed?/1 and found?/1" do
    test "each predicate matches one state" do
      assert PullRequestType.open?(state(:open))
      refute PullRequestType.open?(state(:merged))

      assert PullRequestType.merged?(state(:merged))
      refute PullRequestType.merged?(state(:closed))

      assert PullRequestType.closed?(state(:closed))
      refute PullRequestType.closed?(state(:merged))
    end

    test "found? is true for each state except :not_found" do
      assert PullRequestType.found?(state(:open))
      assert PullRequestType.found?(state(:closed))
      assert PullRequestType.found?(state(:merged))
      assert PullRequestType.found?(state(:invalid_state))
      refute PullRequestType.found?(state(:not_found))
    end
  end

  describe "dump/1" do
    test "returns the lookup" do
      state = %{state: :not_found, number: nil, title: nil, body: nil, url: nil}

      assert {:ok, document} = PullRequestType.dump(state)
      assert PullRequestType.load(document) == {:ok, state}
    end
  end

  @spec state(PullRequestType.pull_request_state()) :: PullRequestType.state()
  defp state(state), do: %{state: state, number: nil, title: nil, body: nil, url: nil}
end
