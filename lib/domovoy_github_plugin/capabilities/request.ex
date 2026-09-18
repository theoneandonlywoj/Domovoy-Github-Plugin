defmodule DomovoyGithubPlugin.Capabilities.Request do
  @moduledoc """
  Sends the requests of the GitHub capabilities through `Req`.

  Every capability that talks to GitHub comes through this module. It finds the
  configuration file from a working directory, reads the access token and the
  timeouts once per call, and sets the headers of the REST API. A successful
  call gives the decoded body. A failed call gives a `failure/0` with the HTTP
  status and the message of GitHub. A failure before GitHub answered has no
  status.

  `list/4` follows the `Link` header of GitHub. Therefore a capability that
  lists gets every page and not the first thirty items. `download/2` keeps the
  body as it is. `graphql/3` sends a query to the GraphQL API of GitHub.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.Request.next_page_url([
      ...>   ~s(<https://api.github.com/repos/o/r/pulls?page=2>; rel="next")
      ...> ])
      "https://api.github.com/repos/o/r/pulls?page=2"
  """

  alias DomovoyGithubPlugin.Capabilities

  @typedoc "Why a request failed: the HTTP status, or `nil` when GitHub gave no answer."
  @type failure() :: %{status: 100..599 | nil, message: String.t()}

  @typedoc "A successful API call's decoded body, or a failure."
  @type result() :: {:ok, term()} | {:error, failure()}

  @typep settings() :: %{
           token: String.t(),
           connect_timeout_ms: pos_integer(),
           receive_timeout_ms: pos_integer()
         }

  @api_base "https://api.github.com"
  @per_page 100
  @default_max_pages 50
  @next_link_pattern ~r/<(?<url>[^>]+)>;\s*rel="next"/

  @doc """
  Sends one request to the REST API of GitHub and decodes the body.

  `path` starts with `/`. `options` are `Req` options such as `params:` or
  `json:`. A response with an empty body, such as a `204`, gives `{:ok, nil}`.

  ## Equivalent Bash

      gh api --method <METHOD> "<path>"
  """
  @spec request(
          method :: atom(),
          path :: String.t(),
          options :: keyword(),
          working_directory :: String.t()
        ) :: result()
  def request(method, path, options, working_directory)
      when is_atom(method) and is_binary(path) and is_list(options) do
    with {:ok, settings} <- settings(working_directory),
         {:ok, response} <- deliver(method, @api_base <> path, options, settings) do
      body(response)
    end
  end

  @doc """
  Gets every page of a list from the REST API of GitHub.

  The request asks for #{@per_page} items per page and follows the `next` link
  until GitHub gives none, or until `max_pages` pages came back. The default is
  #{@default_max_pages} pages.

  Some lists come inside an object, such as `{"check_runs": [...]}`. `into`
  names that key. Without `into` the body itself must be a list.

  ## Options

    * `:into` - the key of the list in the body. The default is none.
    * `:max_pages` - the highest number of pages. The default is
      #{@default_max_pages}.

  ## Equivalent Bash

      gh api --paginate "<path>?per_page=#{@per_page}"
  """
  @spec list(
          path :: String.t(),
          params :: keyword(),
          working_directory :: String.t(),
          opts :: keyword()
        ) :: {:ok, [term()]} | {:error, failure()}
  def list(path, params, working_directory, opts \\ [])
      when is_binary(path) and is_list(params) and is_list(opts) do
    into = Keyword.get(opts, :into)
    max_pages = Keyword.get(opts, :max_pages, @default_max_pages)
    options = [params: Keyword.put(params, :per_page, @per_page)]

    with {:ok, settings} <- settings(working_directory) do
      collect(@api_base <> path, options, settings, into, max_pages, [])
    end
  end

  @doc """
  Gets a body from the REST API of GitHub without decoding it.

  GitHub answers a download with a redirect to a signed URL on another host.
  `Req` follows that redirect and does not send the access token to the other
  host.

  ## Equivalent Bash

      gh api "<path>" > file
  """
  @spec download(path :: String.t(), working_directory :: String.t()) ::
          {:ok, binary()} | {:error, failure()}
  def download(path, working_directory) when is_binary(path) do
    with {:ok, settings} <- settings(working_directory),
         {:ok, response} <- deliver(:get, @api_base <> path, [decode_body: false], settings) do
      raw_body(response)
    end
  end

  @doc """
  Sends a query to the GraphQL API of GitHub and gives its `data`.

  GitHub answers a query with errors as a `200` whose body has an `errors`
  list. This function reports that answer as a failure with status `200`.

  ## Equivalent Bash

      gh api graphql -f query='<query>' -F <name>=<value>
  """
  @spec graphql(query :: String.t(), variables :: map(), working_directory :: String.t()) ::
          result()
  def graphql(query, variables, working_directory) when is_binary(query) and is_map(variables) do
    options = [json: %{query: query, variables: variables}]

    with {:ok, body} <- request(:post, "/graphql", options, working_directory) do
      graphql_data(body)
    end
  end

  @doc """
  Reads the URL of the next page from the `Link` headers of GitHub.

  Gives `nil` when there is no next page.

  ## Examples

      iex> DomovoyGithubPlugin.Capabilities.Request.next_page_url([
      ...>   ~s(<https://api.github.com/x?page=3>; rel="next", <https://api.github.com/x?page=5>; rel="last")
      ...> ])
      "https://api.github.com/x?page=3"

      iex> DomovoyGithubPlugin.Capabilities.Request.next_page_url([
      ...>   ~s(<https://api.github.com/x?page=1>; rel="prev")
      ...> ])
      nil

      iex> DomovoyGithubPlugin.Capabilities.Request.next_page_url([])
      nil
  """
  @spec next_page_url(link_headers :: [String.t()]) :: String.t() | nil
  def next_page_url(link_headers) when is_list(link_headers) do
    case Regex.named_captures(@next_link_pattern, Enum.join(link_headers, ", ")) do
      %{"url" => url} -> url
      nil -> nil
    end
  end

  @spec collect(
          url :: String.t(),
          options :: keyword(),
          settings :: settings(),
          into :: String.t() | nil,
          pages_left :: non_neg_integer(),
          acc :: [term()]
        ) :: {:ok, [term()]} | {:error, failure()}
  defp collect(url, options, settings, into, pages_left, acc) do
    with {:ok, response} <- deliver(:get, url, options, settings),
         {:ok, body} <- body(response),
         {:ok, items} <- items(body, into) do
      next_page(response, settings, into, pages_left - 1, acc ++ items)
    end
  end

  @spec next_page(
          response :: Req.Response.t(),
          settings :: settings(),
          into :: String.t() | nil,
          pages_left :: integer(),
          acc :: [term()]
        ) :: {:ok, [term()]} | {:error, failure()}
  defp next_page(_response, _settings, _into, pages_left, acc) when pages_left <= 0,
    do: {:ok, acc}

  defp next_page(response, settings, into, pages_left, acc) do
    case next_page_url(Req.Response.get_header(response, "link")) do
      nil -> {:ok, acc}
      url -> collect(url, [], settings, into, pages_left, acc)
    end
  end

  @spec items(body :: term(), into :: String.t() | nil) :: {:ok, [term()]} | {:error, failure()}
  defp items(body, nil) when is_list(body), do: {:ok, body}

  defp items(%{} = body, into) when is_binary(into) do
    case Map.fetch(body, into) do
      {:ok, items} when is_list(items) -> {:ok, items}
      _other -> no_list(body)
    end
  end

  defp items(body, _into), do: no_list(body)

  @spec no_list(body :: term()) :: {:error, failure()}
  defp no_list(body),
    do: {:error, %{status: nil, message: "GitHub API gave no list: " <> inspect(body)}}

  @spec settings(working_directory :: String.t()) :: {:ok, settings()} | {:error, failure()}
  defp settings(working_directory) do
    config_path = Capabilities.find_config_path(working_directory)

    config =
      case Capabilities.load_config(config_path) do
        {:ok, config} -> config
        :error -> %{}
      end

    case Capabilities.access_token(config) do
      {:ok, token} ->
        {:ok,
         %{
           token: token,
           connect_timeout_ms: Capabilities.connect_timeout_ms(config),
           receive_timeout_ms: Capabilities.receive_timeout_ms(config)
         }}

      :error ->
        {:error, %{status: nil, message: missing_access_token_message(config_path)}}
    end
  end

  @spec deliver(
          method :: atom(),
          url :: String.t(),
          options :: keyword(),
          settings :: settings()
        ) :: {:ok, Req.Response.t()} | {:error, failure()}
  defp deliver(method, url, options, settings) do
    request_options =
      Keyword.merge(
        [
          method: method,
          url: url,
          headers: [
            {"authorization", "Bearer " <> settings.token},
            {"accept", "application/vnd.github+json"},
            {"x-github-api-version", "2022-11-28"}
          ],
          connect_options: [timeout: settings.connect_timeout_ms],
          receive_timeout: settings.receive_timeout_ms
        ],
        options
      )

    case Req.request(request_options) do
      {:ok, %Req.Response{} = response} ->
        {:ok, response}

      {:error, exception} ->
        message = "GitHub API request failed: " <> Exception.message(exception)
        {:error, %{status: nil, message: message}}
    end
  end

  @spec body(response :: Req.Response.t()) :: result()
  defp body(%Req.Response{status: status, body: ""}) when status in 200..299, do: {:ok, nil}
  defp body(%Req.Response{status: status, body: body}) when status in 200..299, do: {:ok, body}
  defp body(%Req.Response{} = response), do: {:error, failure(response)}

  @spec raw_body(response :: Req.Response.t()) :: {:ok, binary()} | {:error, failure()}
  defp raw_body(%Req.Response{status: status, body: body})
       when status in 200..299 and is_binary(body),
       do: {:ok, body}

  defp raw_body(%Req.Response{status: status, body: body}) when status in 200..299,
    do: {:error, %{status: status, message: "GitHub API gave no binary: " <> inspect(body)}}

  defp raw_body(%Req.Response{} = response), do: {:error, failure(response)}

  @spec graphql_data(body :: term()) :: result()
  defp graphql_data(%{"errors" => [_error | _rest] = errors}),
    do: {:error, %{status: 200, message: Enum.map_join(errors, "; ", &error_detail/1)}}

  defp graphql_data(%{"data" => data}) when is_map(data), do: {:ok, data}

  defp graphql_data(body),
    do: {:error, %{status: 200, message: "GitHub GraphQL API gave no data: " <> inspect(body)}}

  @spec failure(response :: Req.Response.t()) :: failure()
  defp failure(%Req.Response{status: status, body: body}),
    do: %{status: status, message: message(body, status)}

  @spec message(body :: term(), status :: integer()) :: String.t()
  defp message(%{"message" => message, "errors" => [_error | _rest] = errors}, _status)
       when is_binary(message),
       do: message <> "; " <> Enum.map_join(errors, "; ", &error_detail/1)

  defp message(%{"message" => message}, _status) when is_binary(message), do: message
  defp message("", status), do: "GitHub API responded with status #{status}"

  defp message(body, status) when is_binary(body) do
    case JSON.decode(body) do
      {:ok, decoded} when is_map(decoded) -> message(decoded, status)
      _other -> body
    end
  end

  defp message(body, _status), do: inspect(body)

  @spec error_detail(error :: term()) :: String.t()
  defp error_detail(%{"message" => message}) when is_binary(message), do: message

  defp error_detail(%{"resource" => resource, "field" => field, "code" => code}),
    do: "#{resource}.#{field} #{code}"

  defp error_detail(error) when is_binary(error), do: error
  defp error_detail(error), do: inspect(error)

  @spec missing_access_token_message(config_path :: String.t()) :: String.t()
  defp missing_access_token_message(config_path) do
    "access_token is not set in #{config_path}; create a personal access token in " <>
      "GitHub at https://github.com/settings/tokens, then set access_token in " <>
      Capabilities.config_relative_path() <> "."
  end
end
