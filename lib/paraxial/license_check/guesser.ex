defmodule Paraxial.Guesser do
  @moduledoc false

  alias Paraxial.License

  @variants %{
    # Apache 2.0
    "Apache 2" => "Apache 2.0",
    "Apache v2.0" => "Apache 2.0",
    "Apache 2 (see the file LICENSE for details)" => "Apache 2.0",
    "Apache-2.0" => "Apache 2.0"
  }

  @doc """
  Turns all variants of the names into a single one.

  Duplicates are removed if found in the list of variants.
  """
  @spec normalize(String.t() | [String.t()] | nil) :: String.t() | [String.t()] | nil
  def normalize(nil), do: nil

  def normalize(name) when is_binary(name) do
    @variants[name] || name
  end

  def normalize(names), do: names |> Enum.map(&normalize/1) |> Enum.uniq()

  def guess(licenses) when is_list(licenses), do: Enum.map(licenses, &guess/1)

  def guess(%License{} = license) do
    hex_metadata_licenses = normalize(license.hex_metadata)
    file_licenses = normalize(license.file)

    conclusion = guess(hex_metadata_licenses, file_licenses)
    Map.put(license, :license, conclusion)
  end

  defp guess([], nil), do: "Undefined"
  defp guess(nil, nil), do: "Undefined"
  defp guess(nil, file), do: file
  defp guess(hex, nil) when length(hex) > 0, do: Enum.join(hex, ", ")
  defp guess(hex, file) when length(hex) == 1 and hd(hex) == file, do: file

  defp guess(hex, file) do
    if file == "Unrecognized license file content" do
      Enum.join(hex, ",")
    else
      file
    end
    #"Unsure (found: " <> Enum.join(hex, "* ") <> "$ " <> file <> ")"
  end
end
