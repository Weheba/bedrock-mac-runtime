use crate::tokens::store::{TokenBackend, TokenStoreError};

pub struct KeychainBackend;

/// Errors returned for an item this process may not use without asking the user:
/// an item created by a differently signed build (ad-hoc builds change identity on
/// every release), a denied prompt, or keychain UI disabled for the process.
fn is_access_error(err: &keyring_core::Error) -> bool {
    matches!(
        err,
        keyring_core::Error::PlatformFailure(_) | keyring_core::Error::NoStorageAccess(_)
    )
}

impl TokenBackend for KeychainBackend {
    fn get(&self, key: &str) -> Result<Option<Vec<u8>>, TokenStoreError> {
        let entry = crate::secrets::get_entry(key)?;
        match entry.get_secret() {
            Ok(bytes) => Ok(Some(bytes)),
            Err(keyring_core::Error::NoEntry) => Ok(None),
            // Treat an unreadable item as absent: callers then sign in or provision
            // again and `set` replaces the item with one this build owns. Never retry
            // the read, which is what produced one password prompt per item.
            Err(e) if is_access_error(&e) => Ok(None),
            Err(e) => Err(e.into()),
        }
    }

    fn set(&self, key: &str, value: &[u8]) -> Result<(), TokenStoreError> {
        let entry = crate::secrets::get_entry(key)?;
        match entry.set_secret(value) {
            Ok(()) => Ok(()),
            Err(e) if is_access_error(&e) => {
                // Updating an item owned by another code identity needs its ACL; deleting
                // does not. Replace it once.
                let _ = entry.delete_credential();
                Ok(entry.set_secret(value)?)
            }
            Err(e) => Err(e.into()),
        }
    }

    fn remove(&self, key: &str) -> Result<(), TokenStoreError> {
        match crate::secrets::get_entry(key)?.delete_credential() {
            Ok(()) | Err(keyring_core::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.into()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::is_access_error;

    #[test]
    fn access_errors_are_recognised() {
        let platform = keyring_core::Error::PlatformFailure(Box::new(std::io::Error::other("-25308")));
        let storage = keyring_core::Error::NoStorageAccess(Box::new(std::io::Error::other("-61")));
        assert!(is_access_error(&platform));
        assert!(is_access_error(&storage));
        assert!(!is_access_error(&keyring_core::Error::NoEntry));
    }
}
