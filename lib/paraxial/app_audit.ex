defmodule Paraxial.AppAudit do
  @moduledoc false

  alias Paraxial.Helpers
  require Logger

  def post_app_audit() do
    url = Helpers.get_app_audit_url()
    api_key = Helpers.get_api_key()

    app_map = %{
      api_key: api_key,
      audit_body: get_apps()
    }

    json = Jason.encode!(app_map)

    case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
      {:ok, %{status_code: 200}} ->
        Logger.info("[Paraxial] App Audit upload success")

      _ ->
        Logger.info("[Paraxial] App Audit upload failed")
    end
  end

  defp get_apps() do
    Application.loaded_applications()
    |> Enum.map(fn x -> Tuple.to_list(x) |> Enum.map(fn y -> to_string(y) end) end)
    |> List.insert_at(0, ["erlang_otp", "System version of OTP", System.otp_release()])
    |> List.insert_at(0, get_xz())
  end

  def get_xz do
    try do
      {r, _exit} = System.cmd("xz", ["--version"])
      s = r |> String.trim("\n") |> String.replace("\n", ", ")
      ["xz", "Compression", s]
    rescue
      _ -> ["xz", "Compression", "not installed"]
    end
  end
end
