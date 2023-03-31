defmodule Paraxial.AllowedPlug do
  @moduledoc """
  This plug evaluates if an incoming conn should be
  allowed or blocked.

  It should be placed in the endpoint.ex file of a Phoenix application,
  before the Recorder plug.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    if :persistent_term.get(:valid_config) do
      Paraxial.Crow.eval_http(conn)
    else
      conn
    end
  end
end
