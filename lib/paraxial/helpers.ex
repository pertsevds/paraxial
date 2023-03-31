defmodule Paraxial.Helpers do
  @moduledoc false
  def get_api_key() do
    System.get_env("PARAXIAL_API_KEY") ||
      Application.get_env(:paraxial, :paraxial_api_key)
  end

  def get_cloud_ips() do
    Application.get_env(:paraxial, :fetch_cloud_ips)
  end

  def get_base_url() do
    Application.get_env(:paraxial, :paraxial_url)
  end

  def get_bulk_map() do
    Application.get_env(:paraxial, :bulk)
  end

  def get_trusted_domains() do
    Application.get_env(:paraxial, :trusted_domains)
  end

  def get_ingest_url() do
    get_base_url() <> "/api/ingest"
  end

  def get_abr_url() do
    get_base_url() <> "/api/abr"
  end

  def get_cloud_ips_url() do
    get_base_url() <> "/api/cloud_ips"
  end

  def get_scan_ingest_url() do
    get_base_url() <> "/api/scan"
  end

  def get_path_list(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.map(fn s ->
      if String.starts_with?(s, ":") do
        quote do: _
      else
        s
      end
    end)
  end
end
