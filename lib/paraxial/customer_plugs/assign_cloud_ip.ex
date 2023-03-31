defmodule Paraxial.AssignCloudIP do
  @moduledoc """
  This plug is used to add metadata to the conn assigns if an IP matches a cloud provider.

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
    iptrie = :persistent_term.get({Paraxial.Fetcher, :cloud_trie})
    lookup = Iptrie.lookup(iptrie, conn.remote_ip)

    if is_nil(lookup) do
      assign(conn, :paraxial_cloud_ip, nil)
    else
      assign(conn, :paraxial_cloud_ip, elem(lookup, 1))
    end
  end
end
