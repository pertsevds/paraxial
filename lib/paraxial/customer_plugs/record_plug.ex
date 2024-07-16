defmodule Paraxial.RecordPlug do
  @moduledoc """
  Used to record metadata about requests for processing by Paraxial.io backend.
  """
  alias Paraxial.Helpers
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    if :persistent_term.get(:valid_config) do
      do_call(conn)
    else
      conn
    end
  end

  def do_call(conn) do
    match_plug(conn, conn.method, conn.path_info)
  end

  @only Application.compile_env(:paraxial, :only, nil)
  @except Application.compile_env(:paraxial, :except, nil)
  Logger.info(
    "[Paraxial] only/except must be set at compile time, only: #{inspect(@only)}, except: #{inspect(@except)}"
  )

  cond do
    @only && @except ->
      # Default
      def match_plug(conn, _, _) do
        Paraxial.HTTPBuffer.add_http_event(conn)
        conn
      end

    is_list(@only) ->
      # Generate functions that catch the conn and send it to buffer.
      # Default bottom function does NOT send to buffer.
      for only_map <- @only do
        method = only_map[:method]
        path_list = Helpers.get_path_list(only_map[:path])

        # Dynamically generate match_plug/3 functions that send to buffer
        def match_plug(conn, unquote(method), unquote(path_list)) do
          Paraxial.HTTPBuffer.add_http_event(conn)
          conn
        end
      end

      def match_plug(conn, _, _), do: conn

    is_list(@except) ->
      # Generate functions that catch the conn and do NOT send to buffer.
      # Default bottom function sends to buffer.
      for except_map <- @except do
        method = except_map[:method]
        path_list = Helpers.get_path_list(except_map[:path])

        # Dynamically generate match_plug/3 functions that do NOT send to buffer
        def match_plug(conn, unquote(method), unquote(path_list)) do
          conn
        end
      end

      def match_plug(conn, _, _) do
        Paraxial.HTTPBuffer.add_http_event(conn)
        conn
      end

    true ->
      # Default
      def match_plug(conn, _, _) do
        Paraxial.HTTPBuffer.add_http_event(conn)
        conn
      end
  end
end
