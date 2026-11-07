module
public import Veil

-- Original Grand MIT fixture. Explicit-state Veil model, no SMT axioms.
veil module HoldVoid
individual released : Bool
individual confirmed : Bool
#gen_state

after_init {
  released := false
  confirmed := false
}

action request_void {
  released := false
}

action terminal_confirmation {
  confirmed := true
  released := true
}

safety [no_premature_release] released → confirmed
#gen_spec
#model_check interpreted {} {} (sequential := true)
end HoldVoid
