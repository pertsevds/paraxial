defmodule Paraxial.FreeCheck do
  @moduledoc false

  alias Paraxial.Helpers

  # This is not a security barrier, you can override this on the client.
  # The backend will not accept HTTP events for free tier, all it will do
  # is burn client bandwidth.
  def req do
    # Send HTTP request to backend
    api_key = Helpers.get_api_key()
    m = %{api_key: api_key}
    json = Jason.encode!(m)
    url = Helpers.get_free_tier_url()

    # expected values of free?
    # true, false, :json_error, :http_error
    free? =
      case HTTPoison.post(url, json, [{"Content-Type", "application/json"}]) do
        {:ok, %{body: body}} ->
          case Jason.decode(body) do
            {:ok, %{"free_tier" => free_tier}} ->
              free_tier

            _any_json ->
              :json_error
          end

        _any_resp ->
          :http_error
      end

    if free? == true do
      :ets.insert(:parax_meta, {:free_tier, true})
    else
      :ok
    end

  end

end
