defmodule Mix.Tasks.Paraxial.Scan do
  use Mix.Task
  require Logger

  alias Paraxial.Scan
  alias Paraxial.Helpers

  @impl Mix.Task
  def run(_) do
    HTTPoison.start()
    api_key = Helpers.get_api_key()

    if api_key == nil do
      Logger.warn("[Paraxial] API key NOT found, scan results cannot be uploaded")
    else
      Logger.info("[Paraxial] API key found, scan results will be uploaded")
    end

    sobelow =
      Task.async(fn ->
        System.cmd("mix", ["sobelow", "--private", "--skip", "--format", "json"])
      end)

    deps_audit =
      Task.async(fn ->
        System.cmd("mix", ["deps.audit"])
      end)

    hex_audit =
      Task.async(fn ->
        System.cmd("mix", ["hex.audit"])
      end)

    {sobelow, _exit_code} = Task.await(sobelow, :infinity)
    {deps_audit, _exit_code} = Task.await(deps_audit, :infinity)
    {hex_audit, _exit_code} = Task.await(hex_audit, :infinity)

    sl = Scan.make_sobelow(sobelow)
    dl = Scan.make_deps(deps_audit)
    hl = Scan.make_hex(hex_audit)

    findings = List.flatten([sl, dl, hl])

    scan = %Scan{
      timestamp: Scan.get_timestamp(),
      findings: findings,
      api_key: "REDACTED"
    }

    IO.inspect(scan, label: "[Paraxial] Scan findings")
    scan = Map.put(scan, :api_key, api_key)

    json = Jason.encode!(scan)
    url = Helpers.get_scan_ingest_url()
    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
      {:ok, %{body: body}} ->
        if String.contains?(body, "Scan written successfully") do
          Logger.info("[Paraxial] Scan upload success")
        else
          Logger.warn("[Paraxial] Scan upload failed, check configuration.")
        end
      _ ->
        Logger.warn("[Paraxial] Scan upload failed, check configuration.")
    end
  end
end
