defmodule Paraxial.PHPAttackPlug do
  @moduledoc """
  Plug to ban IPs sending requests that end in .php

  Most Elixir and Phoenix applications do not have routes ending in .php,
  so this is a strong signal an IP is malicious. The default ban length
  is one hour, this can be configured when setting the plug in your
  endpoint.ex file:

    plug Paraxial.PHPAttackPlug, length: :week
    plug HavanaWeb.Router  # Your application name will be different

  Valid options for :length are :hour, :day, :week, :infinity
  """
  import Plug.Conn
  require Logger

  @valid_lengths [:hour, :day, :week, :infinity]
  @default_length :hour
  @ban_message "Sent request ending in .php"

  def init(opts) do
    length = Keyword.get(opts, :length, @default_length)

    if length in @valid_lengths do
      opts
    else
      Logger.warning("[Paraxial] Invalid option for Paraxial.PHPAttackPlug: #{length}, using #{@default_length}")
      [length: @default_length]
    end
  end

  def call(conn, opts) do
    if php_request?(conn.request_path) do
      length = Keyword.get(opts, :length)

      Task.start(fn ->
        Paraxial.ban_ip(conn.remote_ip, length, @ban_message)
      end)

      conn
      |> halt()
      |> send_resp(403, Jason.encode!(%{"error" => "banned"}))
    else
      conn
    end
  end

  defp php_request?(path) do
    String.ends_with?(String.downcase(path), ".php")
  end
end
