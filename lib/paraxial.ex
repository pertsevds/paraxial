defmodule Paraxial do
  @moduledoc """
  Paraxial.io functions for use by users.
  """

  alias Paraxial.Helpers

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
