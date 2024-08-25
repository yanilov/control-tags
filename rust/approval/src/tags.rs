use const_format::concatcp;

mod prefix {
    pub(super) const CONTROL: &str = "tagctl/v1";
}

pub(crate) const KEY_ADMIN: &str = concatcp!(prefix::CONTROL, "/", "admin");
pub(crate) const KEY_ADMIN_TICKET: &str = concatcp!(KEY_ADMIN, "/", "ticket");
pub(crate) const KEY_SYS_MPA: &str = concatcp!(prefix::CONTROL, "system", "/", "mpa");
