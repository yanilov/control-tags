#![allow(dead_code)]
mod common;

/// Assertion of dishonest flows. These are the flows that should be denied by the system.
mod soundness {
    #[test]
    fn given_no_mpa_ticket_when_adding_resource_seal_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_no_mpa_ticket_when_removing_resource_seal_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_no_mpa_ticket_when_calling_sealed_action_on_tagged_resource_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_mpa_ticket_when_calling_sealed_action_on_tagged_resource_outside_seal_grant_then_denied() {
        unimplemented!()
    }
}

/// Assertion of honest flows. These are the flows that should be allowed by the system.
mod correctness {

    #[test]
    fn given_mpa_ticket_when_adding_resource_seal_then_allowed() {
        unimplemented!()
    }

    #[test]
    fn given_mpa_ticket_when_removing_resource_seal_then_allowed() {
        unimplemented!()
    }

    #[test]
    fn given_mpa_ticket_when_calling_sealed_action_on_tagged_resource_within_seal_grant_then_allowed() {
        unimplemented!()
    }
}
