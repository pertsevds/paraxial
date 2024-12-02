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
    Application.get_env(:paraxial, :paraxial_url) ||
      "https://app.paraxial.io"
  end

  def get_bulk_map() do
    Application.get_env(:paraxial, :bulk)
  end

  def get_trusted_domains() do
    Application.get_env(:paraxial, :trusted_domains)
  end

  def get_exploit_guard() do
    Application.get_env(:paraxial, :exploit_guard)
  end

  def get_app_audit() do
    Application.get_env(:paraxial, :app_audit)
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

  def get_exploit_ingest_url() do
    get_base_url() <> "/api/exploit"
  end

  def get_app_audit_url() do
    get_base_url() <> "/api/app_audit"
  end

  def get_github_app_url() do
    get_base_url() <> "/api/github_app"
  end

  def get_gitlab_app_url() do
    get_base_url() <> "/api/gitlab_app"
  end

  def get_sarif_url() do
    get_base_url() <> "/api/sarif"
  end

  def get_post_rule_event_url() do
    get_base_url() <> "/api/post_rule_event"
  end

  def get_free_tier_url() do
    get_base_url() <> "/api/free_tier"
  end

  def get_ban_url() do
    get_base_url() <> "/api/ruby_ban_x"
  end

  def version() do
    "2.8.0"
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
