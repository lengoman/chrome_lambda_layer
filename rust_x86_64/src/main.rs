use lambda_runtime::{service_fn, Error, LambdaEvent};
use serde::{Deserialize, Serialize};
use chromiumoxide::browser::{Browser, BrowserConfig, HeadlessMode};
use chromiumoxide::page::ScreenshotParams;
use futures_util::StreamExt;
use base64::{Engine as _, engine::general_purpose::STANDARD};
use tracing::info;
use std::fs;
use std::path::Path;
use std::collections::HashMap;
use tokio::time::{timeout, Duration};

#[derive(Deserialize)]
struct Request {
    url: String,
    mode: Option<String>, // "html" or "screenshot", defaults to "screenshot"
}

#[derive(Serialize)]
struct Response {
    message: String,
    title: String,
    url: String,
    content_length: Option<usize>,
    screenshot_size: Option<usize>,
    screenshot: Option<String>,
    html: Option<String>,
}

fn list_directory_contents(path: &Path, depth: usize) {
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries {
            if let Ok(entry) = entry {
                let path = entry.path();
                info!("{}Found: {:?}", "  ".repeat(depth), path);
                if path.is_dir() {
                    list_directory_contents(&path, depth + 1);
                }
            }
        }
    }
}

async fn function_handler(event: LambdaEvent<Request>) -> Result<Response, Error> {
    let url = event.payload.url;
    let mode = event.payload.mode.unwrap_or_else(|| "screenshot".to_string());
    info!("Processing URL: {} with mode: {}", url, mode);
    
    // Debug: List contents of /opt directory recursively
    info!("Listing contents of /opt directory recursively:");
    list_directory_contents(Path::new("/opt"), 0);
    
    // Set up environment variables for Chrome
    let mut env = HashMap::new();
    env.insert("LD_LIBRARY_PATH".to_string(), "/opt/chromium/lib:/opt/chromium/swiftshader".to_string());
    let chrome_path = std::env::var("CHROME_PATH").unwrap_or_else(|_| "/opt/chromium/chrome".to_string());
    
    // Configure browser launch options with necessary flags
    let browser_config = BrowserConfig::builder()
        .disable_default_args()
        .headless_mode(HeadlessMode::True)
        .args(vec![
            "--no-sandbox",
            "--disable-setuid-sandbox",
            "--disable-dev-shm-usage",
            "--disable-gpu",
            "--disable-namespace-sandbox",
            "--headless=new",
            "--single-process",
            "--enable-javascript",
            "--js-flags=--expose-gc",
            "--enable-features=NetworkService,NetworkServiceInProcess",
            "--disable-web-security",
            "--allow-running-insecure-content",
            "--disable-site-isolation-trials",
            "--disable-features=IsolateOrigins,site-per-process",
            "--window-size=1920,1080",
            "--start-maximized",
            "--disable-extensions",
            "--disable-default-apps",
            "--disable-popup-blocking",
            "--disable-notifications",
            "--disable-infobars",
            "--disable-blink-features=AutomationControlled",
            "--disable-background-networking",
            "--disable-background-timer-throttling",
            "--disable-backgrounding-occluded-windows",
            "--disable-breakpad",
            "--disable-client-side-phishing-detection",
            "--disable-component-update",
            "--disable-domain-reliability",
            "--disable-features=AudioServiceOutOfProcess",
            "--disable-hang-monitor",
            "--disable-ipc-flooding-protection",
            "--disable-prompt-on-repost",
            "--disable-renderer-backgrounding",
            "--disable-sync",
            "--force-color-profile=srgb",
            "--metrics-recording-only",
            "--no-first-run",
            "--password-store=basic",
            "--use-mock-keychain",
            "--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36",
        ])
        .chrome_executable(&chrome_path)
        .build()?;

    info!("Launching browser with configuration...");
    let (mut browser, mut handler) = Browser::launch(browser_config).await?;
    info!("Browser launched successfully");
    
    let handle = tokio::spawn(async move {
        while let Some(_) = handler.next().await {}
    });

    // Wrap the browser operations in a timeout
    let result = timeout(Duration::from_secs(60), async {
        info!("Creating new page...");
        let page = browser.new_page("about:blank").await?;
        info!("Page created successfully");
        
        info!("Navigating to URL: {}", url);
        // Try a different approach to navigation
        match page.goto(&url).await {
            Ok(_) => info!("Initial navigation completed"),
            Err(e) => {
                info!("Initial navigation failed: {}", e);
                // Try again with a different approach
                info!("Trying alternative navigation method...");
                let js_code = format!("window.location.href = '{}'", url);
                page.evaluate(js_code).await?;
                info!("Alternative navigation completed");
            }
        }
        
        info!("Waiting for navigation to complete...");
        match page.wait_for_navigation().await {
            Ok(_) => info!("Navigation completed"),
            Err(e) => {
                info!("Navigation wait failed: {}", e);
                // Continue anyway, the page might still be usable
            }
        }
        
        info!("Waiting for network to be idle...");
        // Wait for the page to settle
        tokio::time::sleep(Duration::from_secs(5)).await;
        
        // Try to evaluate if the page is ready
        match page.evaluate("document.readyState").await {
            Ok(state) => info!("Page ready state: {:?}", state),
            Err(e) => info!("Failed to get ready state: {}", e),
        }
        
        info!("Getting page title...");
        let title = match page.get_title().await {
            Ok(Some(t)) => t,
            Ok(None) => "No title found".to_string(),
            Err(e) => {
                info!("Failed to get title: {}", e);
                "Error getting title".to_string()
            }
        };
        info!("Page title: {}", title);
        
        let mut response = Response {
            message: "Successfully processed page".to_string(),
            title,
            url,
            content_length: None,
            screenshot_size: None,
            screenshot: None,
            html: None,
        };

        match mode.as_str() {
            "html" => {
                info!("Getting page content...");
                let content = page.content().await?;
                info!("Content length: {} bytes", content.len());
                response.content_length = Some(content.len());
                response.html = Some(content);
            },
            "screenshot" => {
                info!("Taking screenshot...");
                // Wait a bit more for any animations to complete
                tokio::time::sleep(Duration::from_secs(2)).await;
                let screenshot = page.screenshot(ScreenshotParams::builder()
                    .capture_beyond_viewport(false)
                    .full_page(false)
                    .omit_background(false)
                    .build()).await?;
                let screenshot_base64 = STANDARD.encode(&screenshot);
                info!("Screenshot size: {} bytes", screenshot.len());
                response.screenshot_size = Some(screenshot.len());
                response.screenshot = Some(screenshot_base64);
            },
            _ => {
                info!("Invalid mode: {}, defaulting to screenshot", mode);
                // Wait a bit more for any animations to complete
                tokio::time::sleep(Duration::from_secs(2)).await;
                let screenshot = page.screenshot(ScreenshotParams::builder()
                    .capture_beyond_viewport(false)
                    .full_page(false)
                    .omit_background(false)
                    .build()).await?;
                let screenshot_base64 = STANDARD.encode(&screenshot);
                info!("Screenshot size: {} bytes", screenshot.len());
                response.screenshot_size = Some(screenshot.len());
                response.screenshot = Some(screenshot_base64);
            }
        }
        
        info!("Closing browser...");
        browser.close().await?;
        handle.abort();
        
        Ok::<Response, Error>(response)
    })
    .await
    .map_err(|_| Error::from("Operation timed out after 60 seconds"))?
    .map_err(|e| Error::from(format!("Browser operation failed: {}", e)))?;

    Ok(result)
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_target(false)
        .without_time()
        .init();

    lambda_runtime::run(service_fn(function_handler)).await
}
