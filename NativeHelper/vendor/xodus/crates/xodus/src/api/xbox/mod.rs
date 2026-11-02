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
    /// user.auth.xboxlive.com rejected the ticket.
    UserAuth,
    /// xsts.auth.xboxlive.com rejected the user token (no profile, child account, ...).
    Xsts,
}

impl XboxAuthError {
    pub fn code(self) -> &'static str {
        match self {
            Self::UserTokenFault => "MSA_USER_TOKEN_FAULT",
            Self::UserTokenRequest => "MSA_USER_TOKEN_REQUEST",
            Self::UnsupportedToken => "MSA_UNSUPPORTED_TOKEN",
            Self::UserAuth => "XBOX_USER_AUTH",
            Self::Xsts => "XBOX_XSTS",
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

pub async fn try_run(
    client: &reqwest::Client,
    dev_token: LegacyToken,
    legacy: LegacyToken,
    relying_party: &str,
) -> Result<XstsResponse, XboxAuthError> {
    let user_token = crate::api::live::exchange_user_token(
        client,
        legacy,
        "USERNAME".to_string(),
        dev_token,
        None,
        Some("Silent".to_string()),
        "{d6d5a677-0872-4ab0-9442-bb792fce85c5}".to_string(),
        &[(
            "user.auth.xboxlive.com".to_owned(),
            Some(soap::PolicyReference::mbi_ssl()),
        )],
    )
    .await
    .map_err(|_| XboxAuthError::UserTokenRequest)?;

    let user_token: Token = match user_token {
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
    let resp = authenticate_xbox_user(client, user_token)
        .await
        .map_err(|_| XboxAuthError::UserAuth)?;

    request_xsts_token(client, resp.token, relying_party)
        .await
        .map_err(|_| XboxAuthError::Xsts)
}
