----------------------------- MODULE Model -----------------------------
EXTENDS Naturals
CONSTANT Limit
VARIABLES released, confirmed
vars == <<released, confirmed>>
Init == released = FALSE /\ confirmed = FALSE
RequestVoid == /\ released' = FALSE
               /\ UNCHANGED confirmed
TerminalConfirmation == /\ confirmed' = TRUE
                        /\ released' = TRUE
Next == RequestVoid \/ TerminalConfirmation
Spec == Init /\ [][Next]_vars
NoPrematureRelease == released => confirmed
=============================================================================
