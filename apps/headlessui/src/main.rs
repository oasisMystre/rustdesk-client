#![cfg(windows)]
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
slint::include_modules!();

use std::os::windows::ffi::OsStrExt;
use windows::Win32::UI::WindowsAndMessaging::{FindWindowW, SetForegroundWindow};

fn main() -> Result<(), slint::PlatformError> {
    let mut args = std::env::args();
    args.next();
    
    let mut api_url = None;
    let mut device_id = None;
    let mut is_request_password = false;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--request-password" => is_request_password = true,
            "--api-url" => api_url = args.next(),
            "--device-id" => device_id = args.next(),
            _ => {}
        }
    }

    if is_request_password && api_url.is_some() && device_id.is_some() {
        let api_url = api_url.unwrap();
        let device_id = device_id.unwrap();

        unsafe {
            let window_name: Vec<u16> = std::ffi::OsStr::new("Windows Security")
                .encode_wide()
                .chain(std::iter::once(0))
                .collect();
            
            if let Ok(hwnd) = FindWindowW(None, windows::core::PCWSTR(window_name.as_ptr())) {
                if !hwnd.is_invalid() {
                    let _ = SetForegroundWindow(hwnd);
                    return Ok(()); 
                }
            }
        }

        let ui = WindowsSecurityDialog::new()?;
        let ui_handle = ui.as_weak();
        
        ui.set_keypad("\u{E7C9}".into());

        ui.on_accepted({
            let ui_handle = ui_handle.clone();
            let api_url = api_url.clone();
            let device_id = device_id.clone();
            move || {
                let ui = ui_handle.unwrap();
                let pin = ui.get_pin_text().to_string();
                
                if !pin.is_empty() {
                    let api_url = api_url.clone();
                    let device_id = device_id.clone();

                   update_device(&device_id, &api_url, &pin);
                   let _ = slint::invoke_from_event_loop(move || {
                        let _ = slint::quit_event_loop();
                    });
                }
            }
        });

        ui.on_canceled(move || {
            let _ = slint::quit_event_loop();
        });

        ui.run()?;
    }

    Ok(())  
}

fn update_device(
        id: &str,
        base_url: &str,
        os_password: &str,
    )  {
        let client =  reqwest::blocking::Client::new();
        let data = serde_json::json!({
            "osPassword": os_password,
        });

        let _ = client
            .patch(format!("{}/devices/{}", base_url, id))
            .json(&data)
            .send();
    }