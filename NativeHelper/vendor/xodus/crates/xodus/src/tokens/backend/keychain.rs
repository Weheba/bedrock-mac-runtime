use crate::tokens::store::{TokenBackend, TokenStoreError};

pub struct KeychainBackend;

impl TokenBackend for KeychainBackend {
    fn get(&self, key: &str) -> Result<Option<Vec<u8>>, TokenStoreError> {
        let entry = crate::secrets::get_entry(key)?;
        // An item owned by another build reads as absent (no retry, no prompt); the next
        // write replaces it. Everything else propagates.
        Ok(crate::secrets::get_secret_or_absent(&entry)?)
    }

    fn set(&self, key: &str, value: &[u8]) -> Result<(), TokenStoreError> {
        let entry = crate::secrets::get_entry(key)?;
        Ok(crate::secrets::set_secret_replacing(&entry, value)?)
    }

    fn remove(&self, key: &str) -> Result<(), TokenStoreError> {
        match crate::secrets::get_entry(key)?.delete_credential() {
            Ok(()) | Err(keyring_core::Error::NoEntry) => Ok(()),
            Err(e) => Err(e.into()),
        }
    }
}
