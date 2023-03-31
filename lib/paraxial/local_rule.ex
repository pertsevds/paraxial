defmodule Paraxial.LocalRule do
  @moduledoc false

  use GenServer
  require Logger

  ## Client

  def start_link(init_map) do
    GenServer.start_link(__MODULE__, init_map, name: init_map.rule_name)
  end

  def get_state(local_rule) do
    GenServer.call(local_rule, :get_state)
  end

  ## Server
  def init(state) do
    Logger.info("[Paraxial] Local rule init rule id #{inspect(state.rule.id)}")

    # Need to trap exits so the terminate callback is called
    Process.flag(:trap_exit, true)

    ets_atom = get_rule_ets_atom(state.rule)

    :ets.new(ets_atom, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.insert(:rule_names, {ets_atom, state.rule})

    schedule_sweep(state)
    {:ok, state}
  end

  def terminate(_reason, state) do
    ets_atom = get_rule_ets_atom(state.rule)
    :ets.delete(ets_atom)
    :ets.delete(:rule_names, ets_atom)
  end

  def get_rule_ets_atom(rule) do
    :"local_rule_#{rule.id}"
  end

  def handle_info(:sweep, state) do
    ets_atom = get_rule_ets_atom(state.rule)
    schedule_sweep(state)
    :ets.delete_all_objects(ets_atom)
    {:noreply, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  defp schedule_sweep(state) do
    Process.send_after(state.rule_name, :sweep, to_milliseconds(state.rule.time_period))
  end

  defp to_milliseconds(s), do: s * 1000

  def rule_match?(conn, rule) do
    r_path = Regex.compile!(rule.path)
    r_methods = Regex.compile!(rule.http_methods)

    path_match = Regex.match?(r_path, conn.request_path)
    method_match = Regex.match?(r_methods, conn.method)
    ban_rule = rule.on_trigger in ["alert_ban", "ban"]

    cond do
      path_match and method_match and ban_rule ->
        true

      true ->
        false
    end
  end
end
