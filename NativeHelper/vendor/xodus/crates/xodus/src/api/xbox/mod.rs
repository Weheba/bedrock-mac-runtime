use crate::models::live::ExchangeUserTokenOutcome;
use crate::models::secrets::{LegacyToken, Token};
use crate::models::soap;
use crate::models::xbox::XstsResponse;

pub mod auth;
pub mod title;
pub use auth::{authenticate_xbox_user, get_xsts_auth_header, request_xsts_token};

/// Why the user-to-XSTS chain failed. Carries no response contents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum XboxAuthError {
    /// RST2 returned a SOAP fault for the silent user-token exchange. Seen when the
    /// device STS token expired ("The provided proof key is invalid") or the
    /// user's DA token is no longer accepted.
    UserTokenFault,
    /// The RST2 request itself failed (network, malformed response).
    UserTokenRequest,
    /// RST2 issued a token type this flow cannot use.
    UnsupportedToken,
    /// user.auth.xboxlive.com rejected the ticket (HTTP status when known).
    UserAuth(Option<u16>),
    /// xsts.auth.xboxlive.com rejected the user token (no profile, child account, ...).
    Xsts(Option<u16>),
}

impl XboxAuthError {
    pub fn code(self) -> &'static str {
        match self {
            Self::UserTokenFault => "MSA_USER_TOKEN_FAULT",
            Self::UserTokenRequest => "MSA_USER_TOKEN_REQUEST",
            Self::UnsupportedToken => "MSA_UNSUPPORTED_TOKEN",
            Self::UserAuth(Some(400)) => "XBOX_USER_AUTH_400",
            Self::UserAuth(Some(401)) => "XBOX_USER_AUTH_401",
            Self::UserAuth(Some(403)) => "XBOX_USER_AUTH_403",
            Self::UserAuth(None) => "XBOX_USER_AUTH_NETWORK",
            Self::UserAuth(_) => "XBOX_USER_AUTH_HTTP",
            Self::Xsts(Some(400)) => "XBOX_XSTS_400",
            Self::Xsts(Some(401)) => "XBOX_XSTS_401",
            Self::Xsts(Some(403)) => "XBOX_XSTS_403",
            Self::Xsts(None) => "XBOX_XSTS_NETWORK",
            Self::Xsts(_) => "XBOX_XSTS_HTTP",
        }
    }
}

impl std::fmt::Display for XboxAuthError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.code())
    }
}

impl std::error::Error for XboxAuthError {}

pub async fn run(
    client: &reqwest::Client,
    dev_token: LegacyToken,
    legacy: LegacyToken,
    relying_party: &str,
) -> XstsResponse {
    try_run(client, dev_token, legacy, relying_party)
        .await
        .expect("Failed to authenticate Xbox user")
}

pub const TOKEN_BROKER_CLIENT_ID: &str = "000000004424da1f";
const LEGACY_XBOX_HOSTING_APP: &str = "{d6d5a677-0872-4ab0-9442-bb792fce85c5}";

async fn exchange_silent(
    client: &reqwest::Client,
    legacy: &LegacyToken,
    dev_token: &LegacyToken,
    token_broker: bool,
) -> Result<ExchangeUserTokenOutcome, XboxAuthError> {
    let (hosting_app, scope, policy) = if token_broker {
        (
            TOKEN_BROKER_CLIENT_ID.to_string(),
            format!("scope=service::user.auth.xboxlive.com::MBI_SSL&api-version=2.0&clientid={TOKEN_BROKER_CLIENT_ID}"),
            soap::PolicyReference::token_broker(),
        )
    } else {
        (
            LEGACY_XBOX_HOSTING_APP.to_string(),
            "user.auth.xboxlive.com".to_string(),
            soap::PolicyReference::mbi_ssl(),
        )
    };
    crate::api::live::exchange_user_token(
        client,
        legacy.clone(),
        "USERNAME".to_string(),
        dev_token.clone(),
        None,
        Some("Silent".to_string()),
        hosting_app,
        &[(scope, Some(policy))],
    )
    .await
    .map_err(|_| XboxAuthError::UserTokenRequest)
}

pub async fn try_run(
    client: &reqwest::Client,
    dev_token: LegacyToken,
    legacy: LegacyToken,
    relying_party: &str,
) -> Result<XstsResponse, XboxAuthError> {
    // Since ~2026-10-28 Xbox auth fails for the legacy Xbox-app silent exchange
    // (xodus-gaming/xodus#235). Use the token-broker scope the login window itself uses
    // (as in xodus-gaming/xodus#237); keep the legacy chain as a fallback and report the
    // primary chain's error if both fail.
    match run_chain(client, &dev_token, &legacy, relying_party, true).await {
        Ok(xsts) => Ok(xsts),
        Err(primary) => run_chain(client, &dev_token, &legacy, relying_party, false)
            .await
            .map_err(|_| primary),
    }
}

async fn run_chain(
    client: &reqwest::Client,
    dev_token: &LegacyToken,
    legacy: &LegacyToken,
    relying_party: &str,
    token_broker: bool,
) -> Result<XstsResponse, XboxAuthError> {
    let user_token: Token = match exchange_silent(client, legacy, dev_token, token_broker).await? {
        ExchangeUserTokenOutcome::Fault(_) => return Err(XboxAuthError::UserTokenFault),
        ExchangeUserTokenOutcome::Issued(
            soap::BodyContent::RequestSecurityTokenResponseCollection(mut collection),
        ) => {
            if collection.security_tokens.is_empty() {
                return Err(XboxAuthError::UnsupportedToken);
            }
            collection.security_tokens.remove(0).into()
        }
        ExchangeUserTokenOutcome::Issued(soap::BodyContent::RequestSecurityTokenResponse(
            token,
        )) => (*token).into(),
        _ => return Err(XboxAuthError::UnsupportedToken),
    };
    let Token::Compact(user_token) = user_token else {
        return Err(XboxAuthError::UnsupportedToken);
    };
    let resp = match authenticate_xbox_user(client, user_token.clone()).await {
        Ok(resp) => resp,
        // Delegation tickets some accounts now receive are only accepted with `t=`
        // (xodus-gaming/xodus#238).
        Err(e) if e.status() == Some(reqwest::StatusCode::BAD_REQUEST) => {
            let Some(compact) = crate::licensing::content::delegation_as_compact(&user_token) else {
                return Err(XboxAuthError::UserAuth(Some(400)));
            };
            authenticate_xbox_user(client, compact)
                .await
                .map_err(|e| XboxAuthError::UserAuth(e.status().map(|s| s.as_u16())))?
        }
        Err(e) => return Err(XboxAuthError::UserAuth(e.status().map(|s| s.as_u16()))),
    };

    request_xsts_token(client, resp.token, relying_party)
        .await
        .map_err(|e| XboxAuthError::Xsts(e.status().map(|s| s.as_u16())))
}

#[cfg(test)]
mod tests {
    use super::XboxAuthError;

    #[test]
    fn error_codes_are_fixed_and_status_specific() {
        assert_eq!(XboxAuthError::UserTokenFault.code(), "MSA_USER_TOKEN_FAULT");
        assert_eq!(XboxAuthError::UserAuth(Some(401)).code(), "XBOX_USER_AUTH_401");
        assert_eq!(XboxAuthError::UserAuth(None).code(), "XBOX_USER_AUTH_NETWORK");
        assert_eq!(XboxAuthError::Xsts(Some(401)).code(), "XBOX_XSTS_401");
        assert_eq!(XboxAuthError::Xsts(Some(500)).code(), "XBOX_XSTS_HTTP");
    }
}
