defmodule IRCane.Utils.ReverseDNSResolver do
  require Logger

  def resolve(address) do
    with {:ok, parsed_address} <- :inet.parse_address(to_charlist(address)),
         {:ok, {:hostent, hostname, _, _, _, _}} <- :inet.gethostbyaddr(parsed_address) do
      forward_confirmed =
        Enum.any?([:inet, :inet6], fn family ->
          case :inet.getaddrs(hostname, family) do
            {:ok, addresses} -> parsed_address in addresses
            _ -> false
          end
        end)

      hostname = to_string(hostname)

      if forward_confirmed do
        Logger.debug("Reverse DNS lookup for #{address} returned hostname: #{hostname}")
        {:ok, hostname}
      else
        Logger.debug(
          "Reverse DNS lookup for #{address} returned unverified hostname: #{hostname}"
        )

        {:error, :fcrdns_failed}
      end
    else
      {:error, reason} ->
        Logger.debug("Reverse DNS lookup failed for #{address}: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
