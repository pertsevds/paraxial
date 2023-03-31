defmodule Paraxial.Application do
  @moduledoc false

  use Application
  require Logger
  alias Paraxial.Helpers

  @impl true
  def start(_type, _args) do
    base_url = Helpers.get_base_url()
    api_key = Helpers.get_api_key()
    fetch_cloud_ips = Helpers.get_cloud_ips()

    config_invalid = is_nil(base_url) or is_nil(api_key)

    children =
      if config_invalid do
        :persistent_term.put(:valid_config, false)
        Logger.info(
          "[Paraxial] Configuration is not valid, agent will not be started"
        )
        []
      else
        :persistent_term.put(:valid_config, true)
        Logger.info("[Paraxial] URL and API key found. Agent will be started")

        # This order is important, Crow holds an ETS table, :rule_names, that
        # CrowSup's local_rule servers call on terminate.
        # If Crow is dead, then the calls will error because :rule_names
        # was deleted due to Crow dying.
        [
          Paraxial.HTTPBuffer,
          Paraxial.Crow,
          {DynamicSupervisor, strategy: :one_for_one, name: Paraxial.CrowSup}
        ]
      end

    case fetch_cloud_ips do
      true ->
        Logger.info("[Paraxial] :fetch_cloud_ips set to true, fetching...")
        Paraxial.Fetcher.add_cloud_ips()

      false ->
        Logger.info("[Paraxial] :fetch_cloud_ips set to false. No request sent.")
        :persistent_term.put({Paraxial.Fetcher, :cloud_trie}, Iptrie.new())

      _ ->
        Logger.info("[Paraxial] :fetch_cloud_ips not set. No request sent.")
        :persistent_term.put({Paraxial.Fetcher, :cloud_trie}, Iptrie.new())
    end

    opts = [strategy: :one_for_one, name: Paraxial.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
