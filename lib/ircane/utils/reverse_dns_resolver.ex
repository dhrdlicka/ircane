defmodule IRCane.Utils.ReverseDNSResolver do
  require Logger

  def resolve(address) do
    with {:ok, parsed_address} <- :inet.parse_address(to_charlist(address)),
         {:ok, {:hostent, hostname, _, _, _, _}} <- :inet.gethostbyaddr(parsed_address),
         :ok <- forward_confirm(hostname, parsed_address) do
      Logger.debug("Reverse DNS lookup for #{address} returned hostname: #{hostname}")
      {:ok, hostname}
    else
      {:error, reason} = error ->
        Logger.debug("Reverse DNS lookup failed for #{address}: #{inspect(reason)}")
        error
    end
  end

  defp forward_confirm(hostname, address) do
    confirmed? =
      Enum.any?([:inet, :inet6], fn family ->
        case :inet.getaddrs(hostname, family) do
          {:ok, addresses} -> address in addresses
          _ -> false
        end
      end)

    if confirmed? do
      :ok
    else
      Logger.debug("Reverse DNS lookup for #{address} returned unverified hostname: #{hostname}")
      {:error, :fcrdns_failed}
    end
  end
end
