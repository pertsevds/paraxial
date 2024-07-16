defmodule Paraxial.Fetcher do
  @moduledoc false

  alias Paraxial.Helpers
  require Logger

  def add_cloud_ips() do
    url = Helpers.get_cloud_ips_url()

    case HTTPoison.get(url) do
      {:ok, %{body: b}} ->
        ip_trie = :erlang.binary_to_term(b)
        :persistent_term.put({__MODULE__, :cloud_trie}, ip_trie)

      _ ->
        Logger.error("[Paraxial] :fetch_cloud_ips failed, agent will behave as if set to false")
        :persistent_term.put({__MODULE__, :cloud_trie}, Iptrie.new())
    end
  end
end
