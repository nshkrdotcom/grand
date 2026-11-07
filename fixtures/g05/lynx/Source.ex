# Original Grand portable Hold Ledger pure transition seam; MIT licensed.
# This is a mathematical state projection, not a remote effect or balance.
defmodule Grand.HoldLedger.Portable do
  # A void REQUEST must retain held capacity until terminal confirmation.
  # The support implementation participates in the Lynx dependency closure.
  def request_void(free), do: Grand.HoldLedger.Support.hold_pending(free)
  def confirm_void(free), do: free + 1
end
