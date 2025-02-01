#![allow(dead_code)]
mod common;

/// Assertion of dishonest flows. These are the flows that should be denied by the system.
mod soundness {
    #[test]
    fn given_grantless_principal_when_attempting_ctl_tagging_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_granted_principal_when_ctl_tagging_outside_grant_area_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_granted_principal_when_tagging_ctl_lookalike_then_denied() {
        unimplemented!()
    }
}

/// Assertion of honest flows. These are the flows that should be allowed by the system.
mod correctness {
    #[test]
    fn given_granted_principal_when_ctl_tagging_within_grant_area_then_allowed() {
        unimplemented!()
    }
}
