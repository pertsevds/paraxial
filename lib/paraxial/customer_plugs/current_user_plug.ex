defmodule Paraxial.CurrentUserPlug do
  @moduledoc """
  If a user's email is stored in `conn.assigns.current_user.email`, you can use this plug to do: `assign(conn, :paraxial_current_user, conn.assigns.current_user.email)`

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
    if conn.assigns.current_user do
      assign(conn, :paraxial_current_user, conn.assigns.current_user.email)
    else
      conn
    end
  end
end
