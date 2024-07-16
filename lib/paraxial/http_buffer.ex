defmodule Paraxial.HTTPBuffer do
  @moduledoc false
  use GenServer

  require Logger

  import Plug.Conn
  import Paraxial.Helpers

  @three_seconds 3 * 1000

  def start_link(state \\ %{}) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  # add_http_event is the only non-genserver function called externally.
  # Adds one http_event to the buffer.
  def add_http_event(conn), do: GenServer.cast(__MODULE__, {:add_http, conn})

  # Only for testing use
  def get_buffer(), do: GenServer.call(__MODULE__, :get_buffer)

  # Only for testing use
  def clear_buffer(), do: GenServer.cast(__MODULE__, :clear_buffer)

  def init(_) do
    schedule_work()
    {:ok, %{}}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @three_seconds)
  end

  # Only for testing
  def handle_call(:get_buffer, _from, state) do
    {:reply, state, state}
  end

  # handle_info is called every n seconds by schedule_work/0,
  # sends one HTTP request to backend and then clears state
  def handle_info(:work, state) do
    # Only send_http when state is NOT empty
    # If state is empty, no request should be sent
    if state != %{} do
      send_http(state)
    end

    schedule_work()
    {:noreply, %{}}
  end

  def send_http(state) do
    j_body = wrap_json(state)

    if :ets.lookup(:parax_meta, :free_tier)[:free_tier] == true do
      # Do not send HTTP events when free tier is set to true
      :ok
    else
      Task.start(fn ->
        HTTPoison.post(get_ingest_url(), j_body, [{"Content-Type", "application/json"}])
      end)
    end
  end

  def wrap_json(state) do
    no_ids = Enum.map(state, fn {_key, value} -> value end)

    %{}
    |> Map.put("http_requests", no_ids)
    |> Map.put("private_api_key", get_api_key())
    |> Jason.encode!()
  end

  # Only for testing
  def handle_cast(:clear_buffer, _state) do
    {:noreply, %{}}
  end

  # This function is typically called twice per incoming request. The reason
  # for this duplication is we want to record incoming requests that 404.
  #
  # Each incoming request has a unique x-request-id, it's used to overwrite the
  # first conn (no response code) with the second (has a response code)
  def handle_cast({:add_http, conn}, state) do
    l = make_map(conn)
    {:noreply, Map.put(state, hd(get_resp_header(conn, "x-request-id")), l)}
  end

  def ip_to_string(ip_tuple) do
    ip_tuple
    |> :inet_parse.ntoa()
    |> to_string()
  end

  def make_map(conn) do
    ip_address = Map.get(conn, :remote_ip) |> ip_to_string()

    http_method = Map.get(conn, :method)
    path = Map.get(conn, :request_path)

    req_headers = Enum.into(conn.req_headers, %{})
    user_agent = req_headers["user-agent"]

    allowed = !conn.halted
    status_code = conn.status

    login_user_name = get_login_user_name(conn)
    login_success = login_success?(conn)

    ambient_user = get_ambient_user(conn)
    inserted_at = DateTime.utc_now()

    # The atoms become strings during JSON encoding
    %{
      ip_address: ip_address,
      http_method: http_method,
      path: path,
      user_agent: user_agent,
      allowed: allowed,
      status_code: status_code,
      login_user_name: login_user_name,
      login_success: login_success,
      ambient_user: ambient_user,
      inserted_at: inserted_at,
      cloud_ip: conn.assigns[:paraxial_cloud_ip],
      host: conn.host
    }
  end

  def login_success?(conn) do
    case conn do
      %{assigns: %{paraxial_login_success: true}} ->
        true

      %{assigns: %{paraxial_login_success: false}} ->
        false

      %{} ->
        nil
    end
  end

  def get_login_user_name(conn) do
    case conn do
      %{assigns: %{paraxial_login_user_name: user_name}} ->
        user_name

      %{} ->
        nil
    end
  end

  # Likely custom, per-application, maybe expose as a behaviour?
  def get_ambient_user(conn) do
    case conn do
      %{assigns: %{paraxial_current_user: e}} ->
        e

      %{} ->
        nil
    end
  end
end
