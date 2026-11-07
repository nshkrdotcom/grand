module
public import Veil

-- Original Grand MIT negative fixture: premature release at request.
veil module HoldVoid
individual released : Bool
individual confirmed : Bool
#gen_state

after_init {
  released := false
  confirmed := false
}

action request_void {
  released := true
}

action terminal_confirmation {
  confirmed := true
  released := true
}

safety [no_premature_release] released → confirmed
#gen_spec
#model_check interpreted {} {} (sequential := true)
end HoldVoid
