#![allow(dead_code)]
mod common;

/// Assertion of dishonest flows. These are the flows that should be denied by the system.
mod soundness {
    #[test]
    fn given_no_mpa_ticket_when_calling_guarded_action_then_denied() {
        unimplemented!()
    }
}

/// Assertion of honest flows. These are the flows that should be allowed by the system.
mod correctness {
    #[test]
    fn given_mpa_ticket_when_calling_guarded_action_then_allowed() {
        unimplemented!()
    }
}
