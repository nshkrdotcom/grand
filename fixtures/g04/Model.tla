---- MODULE Model ----
EXTENDS Naturals
CONSTANT Limit
VARIABLE count
vars == <<count>>
Init == count = 0
Next == /\ count < Limit
        /\ count' = count + 1
Spec == Init /\ [][Next]_vars
Safe == count <= Limit
====
