defmodule Paraxial.HTTPClient.Req do
  @moduledoc false

  @behaviour Paraxial.HTTPClient

  @impl true
  def start do
    ensure_finch()
  end

  @impl true
  def post(url, body, headers) do
    ensure_finch()

    case apply(Req, :post, [url, [body: body, headers: headers, decode_body: false]]) do
      {:ok, response} ->
        {:ok, %{status_code: response.status, body: response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get(url) do
    ensure_finch()

    case apply(Req, :get, [url, [decode_body: false]]) do
      {:ok, response} ->
        {:ok, %{status_code: response.status, body: response.body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_finch do
    Application.ensure_all_started(:finch)

    unless Process.whereis(Req.Finch) do
      apply(Finch, :start_link, [[name: Req.Finch]])
    end
  end
end
