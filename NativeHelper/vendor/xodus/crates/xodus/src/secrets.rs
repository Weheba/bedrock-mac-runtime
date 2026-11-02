#[cfg(feature = "key-chain-file")]
compile_error!("The native launcher helper must never use the plaintext credential backend.");
pub static SERVICE_NAME: &str = "MinecraftMacLauncher Microsoft";

pub fn init_secrets() -> Result<(), keyring_core::Error> {
    #[cfg(feature = "key-chain-file")]
    {
        let store = keyring_core::sample::Store::new_with_backing(
            secrets_backing_file()
                .to_str()
                .expect("Invalid secrets backing path"),
        )?;
        keyring_core::set_default_store(store);
    }

    #[cfg(not(feature = "key-chain-file"))]
    {
        #[cfg(target_os = "linux")]
        {
            keyring_core::set_default_store(dbus_secret_service_keyring_store::Store::new()?);
        }

        #[cfg(target_os = "macos")]
        {
            keyring_core::set_default_store(apple_native_keyring_store::keychain::Store::new()?);
        }

        #[cfg(not(any(target_os = "linux", target_os = "macos")))]
        {
            let store = keyring_core::sample::Store::new_with_configuration(
                &std::collections::HashMap::from([("persist", "true")]),
            )?;
            keyring_core::set_default_store(store);
        }
    }

    Ok(())
}

pub fn get_entry(user: &str) -> Result<keyring_core::Entry, keyring_core::Error> {
    keyring_core::Entry::new(SERVICE_NAME, user)
}

pub fn destroy_secrets() {
    keyring_core::unset_default_store();
}

#[cfg(feature = "key-chain-file")]
fn secrets_backing_file() -> std::path::PathBuf {
    std::env::var_os("HOME")
        .or_else(|| std::env::var_os("USERPROFILE"))
        .map(std::path::PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(".xodus-keyring.ron")
}

// ---- Keychain access without prompts ------------------------------------------
//
// Items created by an earlier, differently signed build (ad-hoc builds change code
// identity every release) fail their legacy-keychain ACL. With keychain UI disabled
// those reads fail with one of the statuses below instead of prompting. Only those
// mean "replace this item"; every other failure (I/O, missing or read-only keychain,
// locked keychain) is propagated unchanged.

/// errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled.
pub const FOREIGN_ITEM_STATUSES: [i32; 3] = [-25308, -25293, -128];
/// errSecDuplicateItem: a stale item blocks the add.
pub const DUPLICATE_ITEM_STATUS: i32 = -25299;

pub fn is_foreign_item_status(status: i32) -> bool {
    FOREIGN_ITEM_STATUSES.contains(&status)
}

/// The OSStatus behind a keyring error, when the platform store reported one.
pub fn os_status(err: &keyring_core::Error) -> Option<i32> {
    match err {
        keyring_core::Error::PlatformFailure(inner)
        | keyring_core::Error::NoStorageAccess(inner) => platform_status(inner.as_ref()),
        _ => None,
    }
}

#[cfg(target_os = "macos")]
fn platform_status(inner: &(dyn std::error::Error + Send + Sync + 'static)) -> Option<i32> {
    inner
        .downcast_ref::<security_framework::base::Error>()
        .map(|e| e.code())
}

#[cfg(not(target_os = "macos"))]
fn platform_status(_inner: &(dyn std::error::Error + Send + Sync + 'static)) -> Option<i32> {
    None
}

/// True when the item exists but belongs to another code identity. A locked keychain
/// also reports errSecInteractionNotAllowed, so it is excluded explicitly.
pub fn is_foreign_item(err: &keyring_core::Error) -> bool {
    os_status(err).is_some_and(is_foreign_item_status) && !keychain_locked()
}

/// Read a secret, treating an item owned by another build as absent.
pub fn get_secret_or_absent(
    entry: &keyring_core::Entry,
) -> Result<Option<Vec<u8>>, keyring_core::Error> {
    match entry.get_secret() {
        Ok(bytes) => Ok(Some(bytes)),
        Err(keyring_core::Error::NoEntry) => Ok(None),
        Err(e) if is_foreign_item(&e) => Ok(None),
        Err(e) => Err(e),
    }
}

/// Write a secret. If the existing item belongs to another build (or a stale
/// duplicate blocks the add), delete it and write once more. Other failures are
/// returned without touching the stored item.
pub fn set_secret_replacing(
    entry: &keyring_core::Entry,
    value: &[u8],
) -> Result<(), keyring_core::Error> {
    match entry.set_secret(value) {
        Ok(()) => Ok(()),
        Err(e)
            if is_foreign_item(&e)
                || (os_status(&e) == Some(DUPLICATE_ITEM_STATUS) && !keychain_locked()) =>
        {
            match entry.delete_credential() {
                Ok(()) | Err(keyring_core::Error::NoEntry) => entry.set_secret(value),
                Err(_) => Err(e),
            }
        }
        Err(e) => Err(e),
    }
}

/// Whether the default (login) keychain is locked.
#[cfg(target_os = "macos")]
pub fn keychain_locked() -> bool {
    use std::ffi::c_void;
    #[link(name = "Security", kind = "framework")]
    unsafe extern "C" {
        fn SecKeychainCopyDefault(keychain: *mut *mut c_void) -> i32;
        fn SecKeychainGetStatus(keychain: *mut c_void, status: *mut u32) -> i32;
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFRelease(cf: *const c_void);
    }
    const UNLOCKED: u32 = 1; // kSecUnlockStateStatus
    unsafe {
        let mut keychain: *mut c_void = std::ptr::null_mut();
        if SecKeychainCopyDefault(&mut keychain) != 0 || keychain.is_null() {
            return false;
        }
        let mut status: u32 = 0;
        let ok = SecKeychainGetStatus(keychain, &mut status) == 0;
        CFRelease(keychain);
        ok && status & UNLOCKED == 0
    }
}

#[cfg(not(target_os = "macos"))]
pub fn keychain_locked() -> bool {
    false
}

#[cfg(test)]
mod access_tests {
    use super::*;

    #[test]
    fn only_acl_statuses_mean_foreign_item() {
        for status in [-25308, -25293, -128] {
            assert!(is_foreign_item_status(status));
        }
        // errSecIO, NoSuchKeychain, ReadOnly, NotAvailable, write permission, duplicate, ok.
        for status in [-36, -25294, -25292, -25291, -61, -25299, 0] {
            assert!(!is_foreign_item_status(status));
        }
    }

    #[test]
    fn non_platform_errors_have_no_status() {
        assert_eq!(os_status(&keyring_core::Error::NoEntry), None);
        let io = keyring_core::Error::PlatformFailure(Box::new(std::io::Error::other("io")));
        assert_eq!(os_status(&io), None);
        assert!(!is_foreign_item(&io));
    }
}
