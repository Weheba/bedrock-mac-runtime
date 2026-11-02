use crate::hardware;
use crate::licensing::splicense::SPLicense;
use crate::licensing::utils::{generate_string, parse_bcrypt_rsa_private};
use crate::models::devicecredential::{Authentication, ClientInfo, DeviceAddRequest, DeviceInfo};
use crate::models::secrets::{Device, Token};
use chrono::{DateTime, Utc};
use crate::models::soap::BodyContent;
use crate::tokens::manager::TokenManager;
use crate::tokens::store::TokenStoreError;

/// Provisions a device (if none is stored yet) or re-authenticates an existing one
/// (if its STS token is missing/expired), persisting the result through `tokens`.
pub async fn ensure_device_credentials(client: &reqwest::Client, tokens: &TokenManager) {
    match tokens.get_device_license() {
        // Provision only when no usable license is stored. A keychain failure
        // (locked, I/O) must not register a phantom device.
        Err(TokenStoreError::NotFound | TokenStoreError::Serde(_)) => {
            provision_device(client, tokens).await
        }
        Err(_) => {}
        Ok(license)
            if tokens
                .get_device_sts_token()
                .map_or(true, |token| device_token_needs_refresh(&token, Utc::now())) =>
        {
            reauthenticate_device(client, tokens, license).await
        }
        Ok(_) => {}
    }
}

/// Re-authenticates the stored device unconditionally, replacing its STS token.
/// Used when Microsoft rejects a token that still looks valid locally
/// ("The provided proof key is invalid"). Provisions a device if none exists.
pub async fn refresh_device_credentials(client: &reqwest::Client, tokens: &TokenManager) {
    match tokens.get_device_license() {
        // Provision only when no usable license is stored. A keychain failure
        // (locked, I/O) must not register a phantom device.
        Err(TokenStoreError::NotFound | TokenStoreError::Serde(_)) => {
            provision_device(client, tokens).await
        }
        Err(_) => {}
        Ok(license) => reauthenticate_device(client, tokens, license).await,
    }
}

/// Refresh margin before the device STS token's own expiry.
const DEVICE_TOKEN_REFRESH_MARGIN_SECS: i64 = 15 * 60;

/// The device STS token is persisted in the keychain and was previously reused
/// forever. Once Microsoft expires it, every user-token exchange faults, so
/// refresh it ahead of its `Expires` timestamp. Tokens without a parseable
/// expiry are kept (no refresh loop on unexpected formats).
pub fn device_token_needs_refresh(token: &Token, now: DateTime<Utc>) -> bool {
    let Token::Legacy(token) = token else {
        return false;
    };
    match DateTime::parse_from_rfc3339(token.lifetime.expires.trim()) {
        Ok(expires) => {
            expires.with_timezone(&Utc) - now
                <= chrono::Duration::seconds(DEVICE_TOKEN_REFRESH_MARGIN_SECS)
        }
        Err(_) => false,
    }
}

async fn provision_device(client: &reqwest::Client, tokens: &TokenManager) {
    let username = format!("02{}", generate_string(14));
    let password = generate_string(20);
    let provision = DeviceAddRequest {
        client_info: ClientInfo::default(),
        authentication: Authentication::new(username.clone(), password.clone()),
        device_info: Some(DeviceInfo {
            id: "DeviceInfo".to_string(),
            components: hardware::probe_provision_components(),
            tpm_info: None,
        }),
    };

    let dev = crate::api::live::login_device_credential(client, provision)
        .await
        .expect("Failed to get device creds");

    let device = Device {
        username: username.clone(),
        password: password.clone(),
        puid: dev.puid,
        hwid: dev.hw_device_id,
        device_id: dev.license.binding.device_id.unwrap_or_default(),
        splicense: dev.license.splicense_block,
    };

    tokens
        .save_device_license(&device)
        .expect("Failed to save device license");

    reauthenticate_device(client, tokens, device).await;
}

async fn reauthenticate_device(client: &reqwest::Client, tokens: &TokenManager, license: Device) {
    let sp_license =
        SPLicense::parse_base64(&license.splicense).expect("Failed to parse SPLicense");
    let clep_sign_state = sp_license.clep_sign_state.expect("Missing clep sign state");
    let key = clep_sign_state.get_rsa_key();
    let private_key = parse_bcrypt_rsa_private(&key).unwrap();
    let resp = crate::api::live::authenticate_device(client, license.username, private_key)
        .await
        .expect("Failed to auth device");

    if let BodyContent::RequestSecurityTokenResponse(resp) = resp.body.body {
        save_device_sts_token(tokens, resp);
    }
}

fn save_device_sts_token(
    tokens: &TokenManager,
    resp: Box<crate::models::soap::RequestSecurityTokenResponse>,
) {
    let key_name = resp
        .requested_security_token
        .encrypted_data
        .as_ref()
        .unwrap()
        .key_info
        .key_name
        .as_ref()
        .unwrap()
        .clone();
    let token = (*resp).into();
    tokens
        .save_device_token(key_name, token)
        .expect("Failed to save device token");
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::secrets::LegacyToken;
    use crate::models::soap::Timestamp;

    fn token(expires: &str) -> Token {
        Token::Legacy(LegacyToken {
            key_name: None,
            token: String::new(),
            binary_secret: None,
            tpm_key: None,
            lifetime: Timestamp { id: None, created: "2026-10-21T06:03:27Z".into(), expires: expires.into() },
        })
    }

    fn at(s: &str) -> DateTime<Utc> {
        DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
    }

    #[test]
    fn expired_device_token_is_refreshed() {
        assert!(device_token_needs_refresh(&token("2026-10-22T06:03:27Z"), at("2026-11-02T04:26:58Z")));
    }

    #[test]
    fn token_close_to_expiry_is_refreshed() {
        assert!(device_token_needs_refresh(&token("2026-11-02T04:30:00Z"), at("2026-11-02T04:26:58Z")));
    }

    #[test]
    fn valid_device_token_is_kept() {
        assert!(!device_token_needs_refresh(&token("2026-11-03T04:26:58Z"), at("2026-11-02T04:26:58Z")));
    }

    #[test]
    fn unparseable_expiry_does_not_loop() {
        assert!(!device_token_needs_refresh(&token("not a date"), at("2026-11-02T04:26:58Z")));
        assert!(!device_token_needs_refresh(&Token::Compact("x".into()), at("2026-11-02T04:26:58Z")));
    }
}
