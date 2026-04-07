defmodule Paraxial.HTTPClient.Httpoison do
  @moduledoc false

  @behaviour Paraxial.HTTPClient

  @impl true
  def post(url, body, headers) do
    ensure_hackney()

    case apply(HTTPoison, :post, [url, body, headers]) do
      {:ok, response} ->
        {:ok, %{status_code: response.status_code, body: response.body}}

      {:error, error} ->
        {:error, error.reason}
    end
  end

  @impl true
  def get(url) do
    ensure_hackney()

    case apply(HTTPoison, :get, [url]) do
      {:ok, response} ->
        {:ok, %{status_code: response.status_code, body: response.body}}

      {:error, error} ->
        {:error, error.reason}
    end
  end

  @impl true
  def start do
    ensure_hackney()
  end

  defp ensure_hackney do
    Application.ensure_all_started(:hackney)
    apply(HTTPoison, :start, [])
  end
end
