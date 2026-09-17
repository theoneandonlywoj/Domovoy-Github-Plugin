# DomovoyGithubPlugin

GitHub capabilities, types, and runners for Domovoy.

Capabilities talk to GitHub through `Req`. Runners and types sit on
`DomovoyCore`. The host owns each `DomovoyCore.Runtime`.

## Installation

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:domovoy_github_plugin, github: "theoneandonlywoj/Domovoy-Github-Plugin"}
  ]
end
```

## Development

Requires Erlang/OTP and Elixir from `.tool-versions`. Fetch dependencies with
`mix deps.get`.

Repository Git hooks are opt-in:

```sh
make hooks-install
```

## Verification

```sh
mix quality
mix test
```
