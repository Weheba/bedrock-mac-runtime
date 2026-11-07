use std::collections::HashMap;

use base64::prelude::*;
use xal::cvlib::CorrelationVector;
//use xal::extensions::CorrelationVectorReqwestBuilder;

use crate::licensing::utils;
use crate::models::devicecredential::License;
use crate::models::licensing::{
    DeviceContext, LicenseContent, LicenseContentRequest, LicenseContentResponse,
    LicenseTokenRequest, LicenseTokenResponse, LicenseUserIdentity,
};

#[derive(Debug, thiserror::Error)]
pub enum LicenseContentError {
    #[error("request error: {0}")]
    Request(#[from] reqwest::Error),

    /// The account has no entitlement for the requested content (not owned, or
    /// not covered by the account's current subscription tier).
    #[error("not entitled to this content: {description}")]
    NotEntitled { description: String },

    /// The licensing service refused the request without a license decision.
    /// The account's Microsoft Store device group is full (satisfaction failure 501).
    #[error("DEVICE_LIMIT_REACHED")]
    DeviceLimit,

    #[error("licensing service returned HTTP {0}")]
    Http(u16),

    #[error("licensing service returned an unreadable response")]
    Decode,
}

/// Some accounts now receive delegation tickets the licensing service only accepts with
/// the `t=` prefix (xodus-gaming/xodus#238). Returns None when the ticket has no `d=` prefix.
pub fn delegation_as_compact(ticket: &str) -> Option<String> {
    ticket.strip_prefix("d=").map(|rest| format!("t={rest}"))
}

async fn send_content_request(
    client: &reqwest::Client,
    device_ms_token: String,
    user_ms_token: String,
    ticket_reference: String,
    content_id: String,
    market: String,
) -> Result<reqwest::Response, reqwest::Error> {
    let cv = CorrelationVector::new();
    client
        .post("https://licensing.mp.microsoft.com/v7.0/licenses/content")
        .header("from", "XboxLicenseManager")
        .header("Authorization", device_ms_token)
        .header("user-agent", "XboxLm-PC/Microsoft.GamingServices_32.107.4002.0_x64__8wekyb3d8bbwe")
        .header("MS-CV", cv.to_string())
        .json(&LicenseContentRequest {
            content_id,
            market,
            client_challenge: "PD94bWwgdmVyc2lvbj0iMS4wIiBlbmNvZGluZz0idXRmLTgiID8+PENsaWVudENoYWxsZW5nZSB4bWxuczp4c2k9Imh0dHA6Ly93d3cudzMub3JnLzIwMDEvWE1MU2NoZW1hLWluc3RhbmNlIiB4bWxuczp4c2Q9Imh0dHA6Ly93d3cudzMub3JnLzIwMDEvWE1MU2NoZW1hIiB4bWxucz0iaHR0cDovL3NjaGVtYXMubWljcm9zb2Z0LmNvbS9vbmVzdG9yZS9zZWN1cml0eS9ta21zL0xpY1JlcS92MSIgVmVyc2lvbj0iMiI+PExpY2Vuc2VQcm90b2NvbFZlcnNpb24+NTwvTGljZW5zZVByb3RvY29sVmVyc2lvbj48U2lnbmluZ0tleVZlcnNpb24+MTwvU2lnbmluZ0tleVZlcnNpb24+PENsaWVudFZlcnNpb24+MjwvQ2xpZW50VmVyc2lvbj48L0NsaWVudENoYWxsZW5nZT4=".into(),
            concurrency_mode: "Rude".into(),
            license_version: 4,
            need_key: true,
            key_only: true,
            device_context: DeviceContext::default(),
            users: HashMap::from_iter(
                [(utils::generate_suid(),
                vec![LicenseUserIdentity {
                    identity_type: "Msa".to_string(),
                    identity_value: user_ms_token,
                    local_ticket_reference: ticket_reference,
                }])],
            ),
        })
        .send()
        .await
}

// we might need a bump in xal-rs concerning reqwest,
// that might block us from using the correlationvector extension
pub async fn get_license_content(
    client: &reqwest::Client,
    device_ms_token: String,
    user_ms_token: String,
    ticket_reference: String,
    content_id: String,
    market: String,
) -> Result<(LicenseContent, License), LicenseContentError> {
    let mut response = send_content_request(
        client,
        device_ms_token.clone(),
        user_ms_token.clone(),
        ticket_reference.clone(),
        content_id.clone(),
        market.clone(),
    )
    .await?;
    // The ticket format has to change on both tickets together (xodus-gaming/xodus#238).
    if response.status() == reqwest::StatusCode::UNAUTHORIZED {
        let device = delegation_as_compact(&device_ms_token);
        let user = delegation_as_compact(&user_ms_token);
        if device.is_some() || user.is_some() {
            response = send_content_request(
                client,
                device.unwrap_or(device_ms_token),
                user.unwrap_or(user_ms_token),
                ticket_reference,
                content_id,
                market,
            )
            .await?;
        }
    }
    let status = response.status();
    let body = response.bytes().await?;
    let content_res = match serde_json::from_slice::<LicenseContentResponse>(&body) {
        Ok(parsed) => parsed,
        Err(_) if !status.is_success() => return Err(LicenseContentError::Http(status.as_u16())),
        Err(_) => return Err(LicenseContentError::Decode),
    };
    let content = match content_res {
        LicenseContentResponse::Success { license } => license,
        LicenseContentResponse::SatisfactionFailure {
            satisfaction_failure,
        } => {
            if satisfaction_failure.code == 501 {
                return Err(LicenseContentError::DeviceLimit);
            }
            return Err(LicenseContentError::NotEntitled {
                description: satisfaction_failure.description,
            });
        }
    };
    let license = &content.keys[0].value;
    let license = BASE64_STANDARD.decode(license).unwrap();
    let license = quick_xml::de::from_str::<License>(&String::from_utf8(license).unwrap()).unwrap();
    Ok((content, license))
}

pub async fn get_license_token(
    client: &reqwest::Client,
    device_ms_token: String,
    user_ms_token: String,
    ticket_reference: String,
    parent_product_id: String,
    products: Vec<String>,
    custom_developer_string: String,
) -> Result<String, Box<dyn std::error::Error>> {
    let response = client
        .post("https://licensing.mp.microsoft.com/v8.0/licenseToken")
        .header("from", "XboxLicenseManager")
        .header("Authorization", device_ms_token)
        .header(
            "user-agent",
            "XboxLm-PC/Microsoft.GamingServices_32.107.4002.0_x64__8wekyb3d8bbwe",
        )
        .json(&LicenseTokenRequest {
            parent_product_id,
            enforce_sellable_by: true,
            related_product_ids: products,
            custom_developer_string,
            beneficiaries: vec![LicenseUserIdentity {
                identity_type: "Msa".to_string(),
                identity_value: user_ms_token,
                local_ticket_reference: ticket_reference,
            }],
        })
        .send()
        .await?;

    let token_resp: LicenseTokenResponse = response.json().await?;

    Ok(token_resp.license_token)
}

#[cfg(test)]
mod ticket_tests {
    use super::delegation_as_compact;

    #[test]
    fn only_delegation_tickets_change_prefix() {
        assert_eq!(delegation_as_compact("d=a.b.c.d.e").as_deref(), Some("t=a.b.c.d.e"));
        assert_eq!(delegation_as_compact("t=abc"), None);
        assert_eq!(delegation_as_compact("abc"), None);
    }
}
