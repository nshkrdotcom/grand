# Original Grand MIT portable law-support dependency.
# This function models a pending request, not confirmation or an I/O effect.
defmodule Grand.HoldLedger.Support do
  def hold_pending(free), do: free
  def terminal_confirmation?(:terminal_void_confirmed), do: true
  def terminal_confirmation?(_), do: false
end
