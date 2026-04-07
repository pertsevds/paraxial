defmodule Paraxial.HTTPClient do
  @moduledoc false
  require Logger

  @callback post(url :: binary(), body :: binary(), headers :: list()) ::
              {:ok, %{status_code: integer(), body: binary()}} | {:error, term()}

  @callback get(url :: binary()) ::
              {:ok, %{status_code: integer(), body: binary()}} | {:error, term()}

  @callback start() :: :ok

  @optional_callbacks start: 0

  def post(url, body, headers) do
    if dep_available?() do
      client().post(url, body, headers)
    else
      log_missing_http_client()
      {:error, :no_http_client}
    end
  end

  def get(url) do
    if dep_available?() do
      client().get(url)
    else
      log_missing_http_client()
      {:error, :no_http_client}
    end
  end

  def start do
    if dep_available?() do
      c = client()
      Logger.info("[Paraxial] HTTP Client Found: #{inspect(c)}")

      if function_exported?(c, :start, 0) do
        c.start()
      end
    end

    :ok
  end

  def dep_available? do
    client() != nil
  end

  def log_missing_http_client do
    Logger.error("[Paraxial] No HTTP client found. Add one of these to your mix.exs deps:")
    Logger.error("[Paraxial]   {:req, \"~> 0.5\"} (recommended)")
    Logger.error("[Paraxial]   {:httpoison, \">= 1.0.0\"} (legacy option)")
  end

  @valid_clients [Paraxial.HTTPClient.Req, Paraxial.HTTPClient.Httpoison]

  defp client do
    case Application.get_env(:paraxial, :http_client) do
      nil -> auto_detect_client()
      explicit when explicit in @valid_clients -> explicit
      invalid ->
        Logger.error("[Paraxial] Invalid :http_client config: #{inspect(invalid)}")
        Logger.error("[Paraxial] Valid options: Paraxial.HTTPClient.Req or Paraxial.HTTPClient.Httpoison")
        nil
    end
  end

  defp auto_detect_client do
    req? = Code.ensure_loaded?(Req)
    httpoison? = Code.ensure_loaded?(HTTPoison)

    cond do
      req? -> Paraxial.HTTPClient.Req
      httpoison? -> Paraxial.HTTPClient.Httpoison
      true -> nil
    end
  end
end
