#![allow(dead_code)]
mod common;

mod soundness {
    #[test]
    fn given_no_mpa_grant_when_attempting_mpa_tagging_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_mpa_grant_and_no_identity_when_attempting_mpa_tagging_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_mpa_grant_when_setting_reflexive_ticket_then_denied() {
        unimplemented!()
    }

    #[test]
    fn given_mpa_grant_when_setting_forged_ticket_then_denied() {
        unimplemented!()
    }

    #[test]
    // unauthorized as broker
    fn given_non_sso_principal_when_setting_soruce_identity_then_denied() {
        unimplemented!()
    }

    #[test]
    #[ignore = "Unsure how to simulate an SSO principal reliably"]
    // sso role using unauthorized source identity when assuming a mirror role
    fn given_sso_principal_when_setting_unauthorized_soruce_identity_then_denied() {
        unimplemented!()
    }

    #[test]
    // source identity cannot be set to nil
    fn given_broker_principal_when_setting_source_identity_to_nil_then_denied() {
        unimplemented!()
    }
}

mod correctness {
    #[test]
    fn given_authorized_broker_principal_when_setting_source_identity_then_allowed() {
        unimplemented!()
    }

    #[ignore = "Unsure how to simulate an SSO principal reliably"]
    fn given_sso_principal_when_setting_rolesession_as_soruce_identity_then_allowed() {
        unimplemented!()
    }

    #[test]
    fn given_granted_principal_when_tagging_valid_mpa_ticket_then_allowed() {
        unimplemented!()
    }
}
