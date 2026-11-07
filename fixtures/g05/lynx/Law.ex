# Original Grand MIT law. Lynx must translate actual Portable and Support code.
defmodule Grand.HoldLedger.Laws do
  use Lynx.Laws

  def capacity_on_void_request(free), do: Grand.HoldLedger.Portable.request_void(free)

  law capacity_held_before_confirmation(free),
    expects: capacity_on_void_request(free) == free,
    proof: ~LEAN"""
    simp [«capacity_held_before_confirmation:ensures/1», «capacity_on_void_request/1»,
      Elixir.Grand.HoldLedger.Portable.«request_void/1»,
      Elixir.Grand.HoldLedger.Support.«hold_pending/1», Erlang.erlang.«==/2»]
    """
end
