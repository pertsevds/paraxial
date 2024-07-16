defmodule Paraxial.Scan do
  @moduledoc false

  alias Paraxial.Finding

  def get_timestamp() do
    DateTime.utc_now()
  end

  def make_license(license_scan) do
    license_scan
    |> Enum.map(fn [dep, version, license] ->
      %Finding{
        source: "license_scan",
        content: %{
          "dependency" => dep,
          "version" => version,
          "license" => license,
          "reason" => "GPL software is not allowed for this site."
        }
      }
    end)
  end

  def make_sobelow(raw_scan) do
    # Input: The raw json output from a sobelow scan
    # Action: Use Jason (it's already in project) to parse, construct findings
    # Returns a list of findings
    case Jason.decode(raw_scan) do
      {:ok, scan_map} ->
        sobelow_get_findings(scan_map)

      {:error, _e} ->
        # Umbrella app
        many_scans = String.split(raw_scan, "\n\n") |> tl()

        Enum.map(many_scans, fn one_scan ->
          string_json = String.split(one_scan, "\n==>") |> hd()

          case Jason.decode(string_json) do
            {:ok, scan_map} ->
              sobelow_get_findings(scan_map)

            _ ->
              []
          end
        end)
        |> List.flatten()
    end
  end

  def sobelow_get_findings(scan_map) do
    # Input: The sobelow map like %{"findings" => %{"high_confidence" => ...}}
    # Output: A list of findings
    Enum.map(scan_map["findings"], fn {confidence, findings} ->
      Enum.map(findings, fn finding ->
        %Finding{
          source: "sobelow",
          content: Map.put(finding, "confidence", confidence)
        }
      end)
    end)
    |> List.flatten()
  end

  def make_deps(raw_deps) do
    raw_deps
    |> String.split("\n\n")
    |> Enum.map(&dep_to_finding/1)
    |> List.flatten()
  end

  def fpart_to_tuple(fpart) do
    fpart
    |> String.split(":", parts: 2)
    |> List.to_tuple()
  end

  def dep_to_finding(dep_string) do
    finding = String.split(dep_string, "\n", trim: true)

    if length(finding) <= 2 do
      []
    else
      fmap =
        finding
        |> Enum.map(&fpart_to_tuple/1)
        |> Map.new()

      %Finding{
        source: "deps.audit",
        content: fmap
      }
    end
  end

  def print_findings(findings) do
    Enum.map(findings, fn finding ->
      IO.puts("[Paraxial] #{finding.source}")
      Enum.each(Map.to_list(finding.content), fn {label, line} ->
        IO.puts("  #{label}: #{line}")
      end)
      IO.puts("")
    end)
  end

  # Input: Raw output from mix hex.audit
  # Returns a list of findings
  def make_hex("No retired packages found\n"), do: []

  def make_hex(raw_hex) do
    raw_lines = String.split(raw_hex, "\n", trim: true)
    raw_findings = tl(raw_lines)

    Enum.map(raw_findings, fn finding ->
      [dep, ver | reason] = String.split(finding, " ", trim: true)

      %Finding{
        source: "hex.audit",
        content: %{
          "dependency" => dep,
          "version" => ver,
          "reason" => Enum.join(reason, " ")
        }
      }
    end)
  end
end
