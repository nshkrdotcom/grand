# Deliberate INVALID mutation of the Grand portable Hold Ledger seam; MIT.
defmodule Grand.HoldLedger.Portable do
  # BUG: releases held capacity at the request, before confirmation.
  def request_void(free), do: Grand.HoldLedger.Support.hold_pending(free) + 1
  def confirm_void(free), do: free + 1
end
