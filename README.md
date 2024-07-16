# Paraxial.io Agent Guide 

## Introduction 

Welcome to the Paraxial.io agent documentation. This page will introduce you to key features of the agent, how to install it in your project, and how to use conn `assigns` for sending select user data to the backend. 

---

### Index

1. Agent Features

2. Detailed Installation Instructions

3. Debugging Installation Errors

4. Paraxial Functions

5. Paraxial Plugs

6. Assigns 

7. Additional Documentation

---

If you are already familiar with the Paraxial.io agent, and are looking for a concise set of steps to install the agent, without exposition, see the [install page.](./documentation/install.md)

## 1. Agent Features 

### Allowing and Blocking Requests

When a request arrives in an application protected by Paraxial.io, the agent determines if the request should be allowed or blocked. A request may be blocked for many reasons, such as matching a user-defined rule, belonging to a cloud provider's IP range, or being placed on a site's ban list by a user. An example of a user defined rule is, "If one IP address sends > 10 login requests in 5 seconds, ban it".

The decision to allow or deny a request is based on the value of `conn.remote_ip`. If you are hosting your Phoenix application behind a proxy, this value is probably different from the real IP of the client. To fix this, use [the remote_ip library.](https://github.com/ajvondrak/remote_ip)

### Cloud IP Range Matching

The agent is able to determine if an incoming request's IP address matches the IP range of several major cloud providers. For more details, see [cloud ip matching.](./documentation/cloud_ips.md)

### Trusted Domains and Bulk Actions

If the Paraxial.io customer application contains code for a bulk action, such as a user sending dozens of emails with a single POST request, the agent can maintain a data structure of "trusted" domains. Users from these trusted domains can be granted a higher threshold for the bulk action, compared with users from untrusted domains. This means `mike@paraxial.io` can send up to 100 emails at a time, while `kyle@10minmail.com` will be limited to 3. 

### Data Forwarding to Paraxial.io Backend

The agent forwards data about incoming requests to the Paraxial.io backend. There are several paraxial_ prefixed assigns available, to add information about the customer application's users to this data. For example, if you want to quickly determine which requests are associated with logged-in users, use the `:paraxial_current_user` assigns.

## 2. Detailed Installation Instructions

### (Optional) Install remote_ip in your application 

If your application is showing a different `conn.remote_ip` than expected, it is probably behind a proxy. Install the [remote_ip](https://github.com/ajvondrak/remote_ip) library to fix this.

### Use plug Plug.RequestId in your application's endpoint.ex file:

The majority of Phoenix applications do this by default. Check your `endpoint.ex` file for the line:

```
  plug Plug.RequestId
```

This plug sets `x-request-id`, which is required for the Paraxial agent to work correctly. If it does not exist, add it to your project. 

### Install `:paraxial` in your application's `mix.exs` file:

```elixir
def deps do
  [
    {:paraxial, "~> 2.7.7"}
  ]
end
```

### Application Configuration:

In your Paraxial.io account, we recommend creating two different sites for your application. One site for development/testing, and one site for production. For your local environment, edit your application's `config/dev.exs`: 

```elixir
config :paraxial,
  paraxial_api_key: System.get_env("PARAXIAL_API_KEY"),
  fetch_cloud_ips: true,
  bulk: %{email: %{trusted: 100, untrusted: 3}},
  trusted_domains: MapSet.new(["paraxial.io", "blackcatprojects.xyz"])
```

Configuration keys and values:

1. `paraxial_api_key` - Found in your site's settings page. Required for secure communication between the agent and Paraxial.io backend service.

2. `paraxial_url` - This is `https://app.paraxial.io`.

3. `fetch_cloud_ips` - By default, Paraxial.io will sent HTTP requests to retrieve the public IP ranges of several cloud providers. If you wish to disable this, set `fetch_cloud_ips` to `false`. When disabled, matching incoming requests against cloud IP addresses will not work. 

4. `bulk` and `trusted_domains` - In the above example, user emails ending in @paraxial.io or @blackcatprojects.xyz will be able to send up to 100 emails. Emails from different domains can only send 3. These values are optional. 

### Configure Plugs

Open `endpoint.ex` and add the required plugs:

```elixir
  plug RemoteIp
  plug Paraxial.AllowedPlug
  plug Paraxial.RecordPlug
  plug HavanaWeb.Router
  plug Paraxial.RecordPlug
```

The duplicated `Paraxial.RecordPlug` before and after the router is intentional, it is done to record requests that fail to match in the router. 

## 3. Debugging Installation Errors

Check that your application is configured correctly.

### 1. Set your application's local logging level to debug. This will allow you to see debug messages from the Paraxial agent. Example `config/dev.exs`:

```
config :logger, level: :debug
```

### 2. Check the Paraxial lines in `config/dev.exs` are similar to:

```elixir
config :paraxial,
  paraxial_api_key: System.get_env("PARAXIAL_API_KEY"),
  fetch_cloud_ips: true,
  bulk: %{email: %{trusted: 100, untrusted: 3}},
  trusted_domains: MapSet.new(["paraxial.io", "blackcatprojects.xyz"])
```

The following values are optional:

- fetch_cloud_ips
- bulk
- trusted_domains

### 3. Start your application locally, read the debug lines from Paraxial. 

Bad start:

```
@ house % mix phx.server
[warning] Paraxial API key not found.
```

This warning means your application is not configured correctly. Check your `config` files. 

Bad start:

```
[info] Paraxial URL and API key found.
[info] [Paraxial] :fetch_cloud_ips not set. No requests sent.
[info] [Paraxial] Agent starting supervisor.
[info] Running HouseWeb.Endpoint with cowboy 2.9.0 at 127.0.0.1:4002 (http)
[info] Access HouseWeb.Endpoint at http://localhost:4002
[error] Task #PID<0.603.0> started from Paraxial.Crow terminating
** (FunctionClauseError) no function clause matching in Access.get/3
```
Check that your `paraxial_url` starts with `https` and not `http`. Also check that your API key is entered correctly. 

Good start:
```
[info] Paraxial URL and API key found.
[info] [Paraxial] :fetch_cloud_ips set to true, fetching...
[debug] [Paraxial] Prefixes downloaded for aws: 8075
[debug] [Paraxial] Prefixes downloaded for azure: 56752
[debug] [Paraxial] Prefixes downloaded for digital_ocean: 1644
[debug] [Paraxial] Prefixes downloaded for gcp: 540
[debug] [Paraxial] Prefixes downloaded for oracle: 492
[debug] [Paraxial] Prefixes length with duplicates: 67503
[debug] [Paraxial] Iptrie count - 39566
[debug] [Paraxial] Iptrie size in MB: 1.233269
[info] [Paraxial] Agent starting supervisor.
[info] Running HouseWeb.Endpoint with cowboy 2.9.0 at 127.0.0.1:4002 (http)
[info] Access HouseWeb.Endpoint at http://localhost:4002
[watch] build finished, watching for changes...
[debug] [Paraxial] HTTPBuffer sending POST request
[debug] :ok
```

## 4. Paraxial Functions

There is only one Paraxial function intended for use by users:

1. `Paraxial.bulk_allowed?/3`

## 5. Paraxial Plugs

The Paraxial.io Agent provides several Plugs to be used in your application code:

1. `Paraxial.AllowedPlug` - Required, this Plug determines if an incoming requests matches your allow/block lists. If a request is halted by this Plug, internally Paraxial will still record it. 

2. `Paraxial.RecordPlug` - Required, records incoming HTTP requests into a local buffer, then sends them to the Paraxial.io backend.

3. `Paraxial.AssignCloudIP` - Optional, if the `remote_ip` of an incoming request matching a cloud provider IP address, this plug will add metadata to the conn via an assigns. For example, if a conn's remote_ip matches aws, this plug will do `assigns(conn, :paraxial_cloud_ip, :aws)`.

4. `Paraxial.BlockCloudIP` - Optional, similar to AssignCloudIP. When a conn matches a cloud provider IP, the assign is updated and the conn is halted, with a 404 response sent to the client. 

5. `Paraxial.CurrentUserPlug` - Optional, only works if `conn.assigns.current_user.email` is set. Sets the :paraxial_current_user assigns by calling `assign(conn, :paraxial_current_user, conn.assigns.current_user.email)`

## 6. Assigns

This is a table of every Paraxial assigns value. To avoid conflict with assigns in your application code, each assigns key is prefixed with `paraxial`. 

| Key                       | Set By           | Type |
| :---                      | :---             | :--- |
| :paraxial_login_success   | User Application | Boolean    |
| :paraxial_login_user_name | User Application | String     |
| :paraxial_current_user    | User Application | String     |
| :paraxial_cloud_ip        | Paraxial Agent   | String (aws, azure, etc.) |


To monitor login attempts, use:

```
assign(conn, :paraxial_login_success, true/false)
```

To monitor the login name for the given login attempt use:

```
assign(conn, :paraxial_login_user_name, "userNameHere")
```

To map incoming requests to the currently logged in user, use:

```
assign(conn, :paraxial_current_user, "userNameHere")
```

The `:paraxial_cloud_ip` assign is set by `Paraxial.AssignCloudIP`. If you do not use this assign anywhere in your application code, and just want to block cloud IPs, use `Paraxial.BlockCloudIP`. Check your configuration to ensure `fetch_cloud_ips: true` is set. 


## 7. Additional Documentation 

[Agent Internals](./documentation/agent.md)

[Cloud IPs](./documentation/cloud_ips.md)

[Brief Install Guide](./documentation/install.md)