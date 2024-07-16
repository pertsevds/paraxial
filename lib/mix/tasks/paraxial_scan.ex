defmodule Mix.Tasks.Paraxial.Scan do
  use Mix.Task
  require Logger

  alias Paraxial.Scan
  alias Paraxial.Helpers

  @gh_app_args ["--github_app", "--install_id", "--repo_owner", "--repo_name", "--pr_number"]
  @flag_args ["--paraxial_url", "--paraxial_api_key"]

  @valid_flags [
    "--github_app",
    "--install_id",
    "--repo_owner",
    "--repo_name",
    "--pr_number",
    "--paraxial_url",
    "--paraxial_api_key",
    "--sobelow-config",
    "--sobelow-skip",
    "--gpl-check",
    "--add-exit-code",
    "--sarif",
    "--no-license-scan"
  ]

  @impl Mix.Task
  def run(args) do

    Enum.each(args, fn arg ->
      if String.starts_with?(arg, "--") do
        if Enum.member?(@valid_flags, arg) == false do
          Logger.warning("[Paraxial] #{arg} not a valid flag. Unexpected behavior may occur.")
        end
      end
    end)

    if "--paraxial_url" in args and "--paraxial_api_key" in args do
      Logger.info("[Paraxial] URL and API key cli flags set correctly, these values will be used")
      cli_map = args_to_map(args, @flag_args)
      cli_url = Map.get(cli_map, "--paraxial_url")
      cli_api_key = Map.get(cli_map, "--paraxial_api_key")
      Application.put_env(:paraxial, :paraxial_url, cli_url)
      Application.put_env(:paraxial, :paraxial_api_key, cli_api_key)
    end

    HTTPoison.start()
    api_key = Helpers.get_api_key()

    if api_key == nil do
      Logger.error("[Paraxial] API key NOT found, scan results cannot be uploaded")
    else
      Logger.info("[Paraxial] API key found, scan results will be uploaded")
    end

    default_sobelow =
      if "--sobelow-skip" in args do
        ["sobelow", "--private", "--skip", "--format", "json"]
      else
        # The reason for this long if statement is that users can do the skips
        # in the .sobelow-conf file. Only throw the error when the skips file
        # exists and the config is not being used.
        if File.exists?("./.sobelow-skips") and not ("--sobelow-config" in args) do
          Logger.warning("[Paraxial] .sobelow-skips found, but --sobelow-skip not set, skips file is being ignored.")
        end
        ["sobelow", "--private", "--format", "json"]
      end

    sobelow_flags =
      cond do
        "--sobelow-config" in args and File.exists?("./.sobelow-conf") == false ->
          Logger.error("[Paraxial] --sobelow-config set, but file .sobelow-conf not found. Default scan will run.")
          default_sobelow

        "--sobelow-config" in args and File.exists?("./.sobelow-conf") == true ->
          Logger.info("[Paraxial] File .sobelow-conf found")
          case File.read!("./.sobelow-conf") |> Code.string_to_quoted() do
            {:ok, conf_list} when is_list(conf_list) ->
              if conf_list[:format] == "json" do
                Logger.info("[Paraxial] In .sobelow-conf format is set to \"json\", file is valid")
                ["sobelow", "--config"]
              else
                Logger.error("[Paraxial] File .sobelow-conf, format must be set to \"json\", got #{to_string(conf_list[:format])}. Default scan will run.")
                default_sobelow
              end
            _ ->
              Logger.error("[Paraxial] File .sobelow-conf is not well formed. Default scan will run.")
              default_sobelow
          end

        File.exists?("./.sobelow-conf") ->
          Logger.warning("[Paraxial] File .sobelow-conf found, but --sobelow-config not set, default scan will run. Pass --sobelow-config to read config.")
          default_sobelow

        true ->
          default_sobelow
      end

    sobelow =
      Task.async(fn ->
        System.cmd("mix", sobelow_flags)
      end)

    deps_audit =
      Task.async(fn ->
        System.cmd("mix", ["deps.audit"])
      end)

    hex_audit =
      Task.async(fn ->
        System.cmd("mix", ["hex.audit"])
      end)

    sobelow_sarif =
      if "--sobelow-skip" in args do
        ["sobelow", "--private", "--skip", "--config", "--format", "sarif"]
      else
        ["sobelow", "--private", "--config", "--format", "sarif"]
      end

    sarif_raw =
      if "--sarif" in args do
          Task.async(fn ->
            System.cmd("mix", sobelow_sarif)
          end)
        else
          Task.async(fn -> {nil, 0} end)
      end

    license_scan =
      if "--gpl-check" in args do
        Task.async(fn ->
          Paraxial.LicenseCheck.scan()
          |> Enum.filter(fn [_, _, ls] -> String.contains?(ls, "GPL") end)
        end)
      else
        Task.async(fn -> [] end)
      end

    {sobelow, _exit_code} = Task.await(sobelow, :infinity)
    {deps_audit, _exit_code} = Task.await(deps_audit, :infinity)
    {hex_audit, _exit_code} = Task.await(hex_audit, :infinity)
    license_scan = Task.await(license_scan, :infinity)

    {sarif_raw, _exit_code} = Task.await(sarif_raw, :infinity)

    sl = Scan.make_sobelow(sobelow)
    dl = Scan.make_deps(deps_audit)
    hl = Scan.make_hex(hex_audit)
    lc = Scan.make_license(license_scan)

    findings = List.flatten([sl, dl, hl, lc])

    scan = %{
      timestamp: Scan.get_timestamp(),
      findings: findings,
      api_key: "REDACTED"
    }

    IO.puts("[Paraxial] Scan resulted in #{length(scan.findings)} findings")
    Scan.print_findings(scan.findings)

    scan =
      if "--no-license-scan" in args do
        scan
        |> Map.put(:api_key, api_key)
      else
        scan
        |> Map.put(:api_key, api_key)
        |> Map.put(:licenses, Paraxial.LicenseCheck.scan())
      end

    json = Jason.encode!(scan)
    url = Helpers.get_scan_ingest_url()

    scan_info =
      case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
        {:ok, %{body: body}} ->
          if String.contains?(body, "Scan written successfully") do
            %{"ok" => scan_info} = Jason.decode!(body)
            Logger.info("[Paraxial] #{scan_info}")
            scan_info
          else
            Logger.error("[Paraxial] Scan upload failed, check configuration.")
            IO.inspect(body, label: "[Paraxial] debug HTTP body")
            :error
          end

        _ ->
          Logger.error("[Paraxial] Scan upload failed, check configuration.")
          :error
      end

    github_resp =
      cond do
        Enum.all?(@gh_app_args, fn a -> a in args end) and scan_info == :error ->
          Logger.error("[Paraxial] Github upload did not run due to original scan upload failure.")
          :error

        Enum.all?(@gh_app_args, fn a -> a in args end) ->
          Logger.info("[Paraxial] Github App Correct Arguments")
          github_app_upload(args, scan_info)

        "--github_app" in args ->
          Logger.error(
            "[Paraxial] --github_app is missing arguments. Required: --install_id, --repo_owner, --repo_name, --pr_number"
          )
          :error

        true ->
          # When the --github_app flag is not present
          :ok
      end

    if "--sarif" in args do
      url = Paraxial.Helpers.get_sarif_url()
      # get the enriched version
      case HTTPoison.post(url, sarif_raw, [{"Content-Type", "application/json"}]) do
        {:ok, %{body: body}} ->
          File.write!("sarif.txt", body)
          Logger.info("[Paraxial] SARIF file written successfully.")
        _ ->
          Logger.error("[Paraxial] SARIF upload failed.")
      end
    end

    if "--add-exit-code" in args and (length(scan.findings) > 0 or scan_info == :error or github_resp == :error) do
      exit({:shutdown, 1})
    end
  end

  def github_app_upload(args, scan_info) do
    regex = ~r/UUID (.+)/
    captures = Regex.run(regex, scan_info, capture: :all_but_first)
    scan_uuid = Enum.at(captures, 0)

    cli_map = args_to_map(args, @gh_app_args)

    censored_backend_map = %{
      "installation_id" => Map.get(cli_map, "--install_id"),
      "repository_owner" => Map.get(cli_map, "--repo_owner"),
      "repository_name" => Map.get(cli_map, "--repo_name"),
      "pull_request_number" => Map.get(cli_map, "--pr_number"),
      "scan_uuid" => scan_uuid,
      "api_key" => "REDACTED"
    }

    IO.inspect(censored_backend_map, label: "[Paraxial] Github Upload info")

    backend_map = Map.put(censored_backend_map, "api_key", Helpers.get_api_key())

    url = Helpers.get_github_app_url()
    json = Jason.encode!(backend_map)

    debug_url =
      "https://github.com/#{cli_map["--repo_owner"]}/#{cli_map["--repo_name"]}/pull/#{cli_map["--pr_number"]}"

    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
      {:ok, %{body: body}} ->
        if String.contains?(body, "Comment created successfully") do
          Logger.info("[Paraxial] Github PR Comment Created successfully")
          Logger.info("[Paraxial] URL: #{debug_url}")
          :ok
        else
          Logger.error("[Paraxial] Github PR Comment failed")
          :error
        end

      _ ->
        Logger.error("[Paraxial] Github PR Comment failed")
        :error
    end
  end

  def args_to_map(args, all_args) do
    Enum.reduce(args, %{prev_val: false}, fn arg, acc ->
      cond do
        arg in all_args ->
          # Create a new key
          acc
          |> Map.put(:prev_val, arg)

        acc[:prev_val] != false ->
          # The previous flag in the list was valid, the current arg is the value
          acc
          |> Map.put(acc[:prev_val], arg)
          |> Map.put(:prev_val, false)

        true ->
          # No valid flag or value for the flag, do nothing
          acc
      end
    end)
    |> Map.delete(:prev_val)
  end
end
