use std::path::Path;

use winreg::{enums::HKEY_CURRENT_USER, RegKey};

use crate::{result::RokitResult, storage::Home};

pub async fn add_to_path(home: &Home) -> RokitResult<bool> {
    // NOTE: Calls to canonicalize may use blocking filesystem
    // operations, so we spawn a task where that's acceptable.
    let task = spawn_blocking(|| {
        let dir = home.path().join("bin").canonicalize()?;

        let key = RegKey::predef(HKEY_CURRENT_USER);
        let env = key.create_subkey("Environment")?.0;
        let path = env.get_value::<String, _>("PATH")?;

        let path_already_exists = path.split(';').any(|entry| {
            Path::new(entry)
                .canonicalize()
                .map(|p| p == dir)
                .unwrap_or_default()
        });

        if path_already_exists {
            Ok(false)
        } else {
            let new_path = format!("{path};{}", dir.display());
            env.set_value("PATH", &new_path)?;
            Ok(true)
        }
    });

    Ok(task??)
}
