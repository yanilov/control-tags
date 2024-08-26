use std::path::PathBuf;

pub struct Configuration {}

impl Configuration {
    pub fn load(_path: Option<PathBuf>) -> Self {
        Self {}
    }
}
