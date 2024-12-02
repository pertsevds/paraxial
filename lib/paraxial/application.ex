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
    exploit_guard = Helpers.get_exploit_guard()
    :persistent_term.put(:exploit_guard, exploit_guard)

    config_invalid = is_nil(base_url) or is_nil(api_key)

    version = Paraxial.Helpers.version()
    children =
      if config_invalid do
        :persistent_term.put(:valid_config, false)
        Logger.info("[Paraxial] v#{version} Configuration is not valid, agent will not be started")
        []
      else
        :persistent_term.put(:valid_config, true)
        Logger.info("[Paraxial] v#{version} URL and API key found. Agent will be started")

        # This order is important, Crow holds an ETS table, :rule_names, that
        # CrowSup's local_rule servers call on terminate.
        # If Crow is dead, then the calls will error because :rule_names
        # was deleted due to Crow dying.
        [
          Paraxial.HTTPBuffer,
          Paraxial.Crow,
          {DynamicSupervisor, strategy: :one_for_one, name: Paraxial.CrowSup},
          {Paraxial.RateLimit, clean_period: :timer.minutes(10)}
        ]
      end

    eg =
      cond do
        exploit_guard == :block ->
          Logger.info("[Paraxial] Exploit Guard set to block mode")
          [Paraxial.ExploitGuard]

        exploit_guard == :monitor ->
          Logger.info("[Paraxial] Exploit Guard set to monitor mode")
          [Paraxial.ExploitGuard]

        is_nil(exploit_guard) ->
          Logger.info(
            "[Paraxial] Exploit Guard not configured, tracing disabled. Valid options are :monitor or :block"
          )

          []

        true ->
          Logger.info(
            "[Paraxial] Exploit Guard bad configuration, tracing disabled. Valid options are :monitor or :block"
          )

          []
      end

    children = eg ++ children

    case fetch_cloud_ips do
      true ->
        Logger.info("[Paraxial] :fetch_cloud_ips set to true, fetching...")
        Paraxial.Fetcher.add_cloud_ips()

      false ->
        Logger.info("[Paraxial] :fetch_cloud_ips set to false. No request sent")
        :persistent_term.put({Paraxial.Fetcher, :cloud_trie}, Iptrie.new())

      _ ->
        Logger.info("[Paraxial] :fetch_cloud_ips not set. No request sent")
        :persistent_term.put({Paraxial.Fetcher, :cloud_trie}, Iptrie.new())
    end

    app_audit = Helpers.get_app_audit()
    if app_audit == false or config_invalid do
      Logger.info("[Paraxial] App Audit disabled, no request sent")
    else
      Task.start(fn -> Paraxial.AppAudit.post_app_audit() end)
    end

    :ets.new(:parax_meta, [
      :set,
      :named_table,
      :public
    ])
    # On startup, run free_check as task
    Task.start(fn -> Paraxial.FreeCheck.req() end)

    opts = [strategy: :one_for_one, name: Paraxial.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
