defmodule Paraxial do
  @moduledoc """
  Paraxial.io functions for use by users.
  """

  alias Paraxial.Helpers
  alias Paraxial.RateLimit

  require Logger

  @doc """
  Ban an IP address, both locally and on the Paraxial.io backend.

  Returns the result of an HTTP request, for example:

  {:ok, "ban created"} - returned on successful ban

  {:error, "ban not created"} - returned if you attempt to ban an IP that is already banned

  {:error, "invalid length, valid options are :hour, :day, :week, :infinity"}

  If you are using this function in a blocking content, call with Task.start, https://hexdocs.pm/elixir/1.12/Task.html#start/1

  - `ip` - Format should match conn.remote_ip, which is a list
  - `length` - Valid options are :hour, :day, :week, :infinity
  - `message` - A text comment, for example "Submitted honeypot HTML form"

  """
  def ban_ip(ip, length, message) do
    # add ip to local_bans
    :ets.insert(:local_bans, {ip})

    # translate IP to string
    ip = Paraxial.HTTPBuffer.ip_to_string(ip)

    # send HTTP request to /api/ruby_ban_x
    m = %{
      "bad_ip" => ip,
      "ban_length" => length,
      "msg" => message,
      "api_key" => Helpers.get_api_key()
    }
    json = Jason.encode!(m)
    url = Helpers.get_ban_url()
    resp = HTTPoison.post(url, json, [{"Content-Type", "application/json"}])

    cond do
      length not in [:hour, :day, :week, :infinity] ->
        {:error, "invalid length, valid options are :hour, :day, :week, :infinity"}
      match?({:error, _}, resp) ->
        {:error, "http request error"}
      match?({:ok, %HTTPoison.Response{status_code: 200, body: "{\"ok\":\"ban not created\"}"}}, resp) ->
        {:error, "ban not created"}
      match?({:ok, %HTTPoison.Response{status_code: 200, body: "{\"ok\":\"ban created\"}"}}, resp) ->
        {:ok, "ban created"}
      true ->
        {:error, "unknown response from server"}
    end
  end


  @doc """
  Rate limiter that will also ban the relevant IP address via Paraxial.io.

  Returns `{:allow, n} or {:deny, n}`

  - `key: String to rate limit on, ex: "login-96.56.162.210", "send-email-michael@paraxial.io"`
  - `seconds: Length of the rate limit rule`
  - `count: Number of times the action can be performed in the seconds time limit`
  - `ban_length: Valid strings are "alert_only", "hour", "day", "week", "infinity"`
  - `ip: Tuple, you can pass conn.remote_ip directly here`
  - `msg: Human-readable string, ex: "> 5 requests in 10 seconds to blackcatprojects.xyz/users/log_in from \#{ip}"`

  ```
  ip_string = conn.remote_ip |> :inet.ntoa() |> to_string()
  key = "user-register-get-\#{ip_string}"
  seconds = 5
  count = 5
  ban_length = "hour"
  ip = conn.remote_ip
  msg = "> 5 requests in 10 seconds to \#{conn.host}/users/log_in from \#{ip_string}"

  case Paraxial.check_rate(key, seconds, count, ban_length, ip, msg) do
    {:allow, _} ->
      # Allow code here
    {:deny, _} ->
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(401, "Banned")
  end
  ```
  """
  def check_rate(key, seconds, count, ban_length, ip, msg) do
    ms = seconds * 1000
    result = RateLimit.check_rate(key, ms, count)
    # {:allow, 3}
    # {:allow, 4}
    # {:allow, 5} <- this call is where the json is POSTed to Paraxial.io
    # {:deny, 5}
    # {:deny, 5}

    if result == {:allow, count} do
      # Send JSON
      post_rule_event(key, seconds, count, ban_length, ip, msg)
      result
    else
      result
    end
  end

  defp post_rule_event(key, seconds, count, ban_length, ip, msg) do
    # Send JSON for the rule event to the Paraxial.io backend

    # key: "login-96.56.162.210", "send-email-michael@paraxial.io", etc
    # seconds: the length of the rate limit rule
    # count: number of times the key can be performed in the seconds time limit
    # ban_length: "alert_only", "hour", "day", "week", "infinity"
    # ip: tuple
    # msg: "> 5 requests in 10 seconds to blackcatprojects.xyz/users/log_in from #{ip}"

    api_key = Helpers.get_api_key()
    m = %{
      "key" => key,
      "time_period" => seconds,
      "n_requests" => count,
      "on_trigger" => ban_length,
      "ip_address" => Tuple.to_list(ip),
      "msg" => msg,
      "api_key" => api_key
    }

    url = Helpers.get_post_rule_event_url()
    json = Jason.encode!(m)

    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200}} ->
        Logger.info("[Paraxial] Post rule event upload success")

      _ ->
        Logger.info("[Paraxial] Post rule event upload failed")
    end
  end

  @doc """
  Given an email, bulk action (such as :email), and count, return true or fase.any()

  Example config:

  ```elixir
  config :paraxial,
    # ...
    bulk: %{email: %{trusted: 100, untrusted: 3}},
    trusted_domains: MapSet.new(["paraxial.io", "blackcatprojects.xyz"])
  ```

  ## Examples

      iex> Paraxial.bulk_allowed?("mike@blackcatprojects.xyz", :email, 3)
      true

      iex> Paraxial.bulk_allowed?("mike@blackcatprojects.xyz", :email, 100)
      true

      iex> Paraxial.bulk_allowed?("mike@test.xyz", :email, 4)
      false

  """
  def bulk_allowed?(email, bulk_action, count) do
    # bulk map:   bulk: %{emails: %{trusted: 100, untrusted: 5}}
    # trusted domains:   trusted_domains: ["blackcatprojects.xyz", "paraxial.io"]

    bulk_map = Helpers.get_bulk_map()
    trusted_domains = Helpers.get_trusted_domains()

    limits = bulk_map[bulk_action]

    if email_trusted?(email, trusted_domains) do
      count <= limits[:trusted]
    else
      count <= limits[:untrusted]
    end
  end

  def email_trusted?(email, trusted_domains) do
    [_h, domain] = String.split(email, "@")
    domain in trusted_domains
  end
end
