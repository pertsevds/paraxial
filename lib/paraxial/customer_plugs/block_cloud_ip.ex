defmodule Paraxial.BlockCloudIP do
  @moduledoc """
  Plug used to block cloud provider IPs.

  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if :persistent_term.get(:valid_config) do
      do_call(conn)
    else
      conn
    end
  end

  def do_call(conn) do
    cloud_iptrie = :persistent_term.get({Paraxial.Fetcher, :cloud_trie})
    cloud_lookup = Iptrie.lookup(cloud_iptrie, conn.remote_ip)

    [allow_trie: allow_trie] = :ets.lookup(:allow_list, :allow_trie)
    allow_lookup = Iptrie.lookup(allow_trie, conn.remote_ip)

    cond do
      allow_lookup && !is_nil(cloud_lookup) ->
        assign(conn, :paraxial_cloud_ip, elem(cloud_lookup, 1))

      is_nil(cloud_lookup) ->
        assign(conn, :paraxial_cloud_ip, nil)

      true ->
        h_conn =
          conn
          |> assign(:paraxial_cloud_ip, elem(cloud_lookup, 1))
          |> halt()

        Paraxial.HTTPBuffer.add_http_event(h_conn)

        h_conn
        |> send_resp(404, Jason.encode!(%{"error" => "banned"}))
    end
  end
end
