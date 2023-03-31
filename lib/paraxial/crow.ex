defmodule Paraxial.Crow do
  @moduledoc false

  use GenServer
  require Logger
  import Plug.Conn
  import Paraxial.Helpers

  alias Paraxial.LocalRule

  @three_seconds 3 * 1000
  @local_bans_clear 30 * 1000
  @max_fail_count 5

  def get_api_key_map() do
    %{api_key: get_api_key()}
    |> Jason.encode!()
  end

  def http_post(url) do
    body = get_api_key_map()
    HTTPoison.post(url, body, [{"Content-Type", "application/json"}])
  end

  def get_allows_bans_rules() do
    url = get_abr_url()

    with {:ok, response} <- http_post(url),
         200 <- response.status_code,
         {:ok, body} <- Jason.decode(response.body),
         false <- is_nil(body["rules"]) do
      rules =
        Enum.map(body["rules"], fn m ->
          for {key, val} <- m, into: %{}, do: {String.to_atom(key), val}
        end)

      al = decode_urls(body, "allows")
      bl = decode_urls(body, "bans")
      %{allows: Iptrie.new(al), bans: Iptrie.new(bl), rules: rules}
    else
      _ ->
        fail_count = :ets.update_counter(:parax_counters, :failed_abr, {2, 1}, {:failed_abr, 0})

        if fail_count > @max_fail_count do
          Logger.warn("[Paraxial] Allows Bans Rules get failed many times, check configuration.")
        end

        fail_count
    end
  end

  def decode_urls(m, a_or_b) do
    l = m[a_or_b]

    Enum.map(l, fn anm ->
      {{List.to_tuple(anm["address"]), anm["netmask"]}, true}
    end)
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    :ets.new(:backend_bans, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.insert(:backend_bans, {:ip_trie, Iptrie.new([])})

    :ets.new(:allow_list, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.insert(:allow_list, {:allow_trie, Iptrie.new([])})

    :ets.new(:local_bans, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(:rule_names, [
      :set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    :ets.new(:parax_counters, [
      :set,
      :named_table,
      :public
    ])

    handle_info(:work, %{})
    clear_local_bans()
    {:ok, %{}}
  end

  def conn_to_local_rs(conn) do
    rules = :ets.tab2list(:rule_names)

    Enum.map(rules, fn {rule_atom, rule} ->
      check_rule_match(conn, rule, rule_atom)
    end)
  end

  def check_rule_match(conn, rule, rule_atom) do
    if LocalRule.rule_match?(conn, rule) do
      case :ets.update_counter(rule_atom, conn.remote_ip, {2, 1}, {conn.remote_ip, 0}) do
        count when count > rule.n_requests ->
          :ets.insert(:local_bans, {conn.remote_ip})
          :halt

        _ ->
          :ok
      end
    else
      # Does not match rule
      :ok
    end
  end

  def conn_to_key(conn) do
    # return {remote_ip, request_id}
    req_id = get_resp_header(conn, "x-request-id")
    {conn.remote_ip, req_id}
  end

  def eval_http(conn) do
    # This function is called on every incoming http request, so
    # performance here is very important.
    #
    # Determine if the conn should be blocked or allowed
    # as fast as possible

    # if conn.remote_ip is found in allow_trie, let it through and don't bother
    # with all the checking logic
    # :ets.insert(:allow_list, {:allow_trie, Iptrie.new([])})
    [allow_trie: allow_trie] = :ets.lookup(:allow_list, :allow_trie)

    if Iptrie.lookup(allow_trie, conn.remote_ip) do
      conn
    else
      [ip_trie: i] = :ets.lookup(:backend_bans, :ip_trie)
      back_l = Iptrie.lookup(i, conn.remote_ip)
      local_l = :ets.lookup(:local_bans, conn.remote_ip)

      # IO.inspect(back_l, label: "backend bans")
      # IO.inspect(local_l, label: "local bans")

      all_ok? = Enum.all?(conn_to_local_rs(conn), fn x -> x == :ok end)

      if is_nil(back_l) and local_l == [] and all_ok? do
        conn
      else
        do_halt_conn(conn)
      end
    end
  end

  def do_halt_conn(conn) do
    halted_conn =
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{"error" => "banned"}))
      |> halt()

    Paraxial.HTTPBuffer.add_http_event(halted_conn)
    halted_conn
  end

  def handle_info(:clear_local_bans, _state) do
    :ets.delete_all_objects(:local_bans)
    :ets.insert(:parax_counters, {:failed_abr, 0})
    clear_local_bans()
    {:noreply, %{}}
  end

  def handle_info(:work, _state) do
    Task.start(fn -> update_abr() end)

    schedule_work()
    {:noreply, %{}}
  end

  def update_abr() do
    maybe_abr_map = get_allows_bans_rules()

    if is_map(maybe_abr_map) do
      :ets.insert(:allow_list, {:allow_trie, maybe_abr_map[:allows]})
      :ets.insert(:backend_bans, {:ip_trie, maybe_abr_map[:bans]})
      update_local_rs(maybe_abr_map[:rules])
    end
  end

  def update_local_rs(rules) do
    # input: a list of new rules
    # action: get current rule server list
    # iterate over rules, remove matching rules from rsl
    # kill every remaining server in rsl

    # if any of the new rules don't have a server, start it
    Enum.map(rules, fn rule ->
      start_local_rule_server(rule)
    end)

    local_rs_map = get_local_rs()

    rs_to_kill =
      Enum.reduce(rules, local_rs_map, fn rule, acc ->
        rule_key = :"Elixir.LocalRule#{rule.id}"

        if Map.has_key?(acc, rule_key) do
          Map.delete(acc, rule_key)
        else
          acc
        end
      end)

    Enum.each(rs_to_kill, fn {_name, pid} ->
      DynamicSupervisor.terminate_child(Paraxial.CrowSup, pid)
    end)
  end

  def get_local_rs() do
    # Return a map of local rule servers
    # %{LocalRule6: pid}
    DynamicSupervisor.which_children(Paraxial.CrowSup)
    |> Enum.map(fn {_, pid, _, _} ->
      {Paraxial.LocalRule.get_state(pid)
       |> Map.get(:rule_name), pid}
    end)
    |> Enum.into(%{})
  end

  def start_local_rule_server(rule) do
    rule_name = :"Elixir.LocalRule#{rule.id}"

    init_state = %{
      http_requests: %{},
      rule_name: rule_name,
      rule: rule
    }

    # If a child has already been started with the rule_name
    # this call returns {:error, {:already_started, pid}}
    DynamicSupervisor.start_child(
      Paraxial.CrowSup,
      {Paraxial.LocalRule, init_state}
    )

    rule_name
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @three_seconds)
  end

  defp clear_local_bans() do
    Process.send_after(self(), :clear_local_bans, @local_bans_clear)
  end
end
