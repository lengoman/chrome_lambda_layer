const puppeteer = require('puppeteer-core');
const chromium = require('@sparticuz/chromium');

exports.handler = async (event) => {
    let browser = null;
    try {
        // Configure browser launch options
        const executablePath = await chromium.executablePath();

        const options = {
            args: chromium.args,
            defaultViewport: chromium.defaultViewport,
            executablePath: executablePath,
            headless: chromium.headless,
            ignoreHTTPSErrors: true
        };

        // Launch the browser
        browser = await puppeteer.launch(options);
        
        // Get URL from event or use default
        const url = event.url || 'https://example.com';
        
        // Create a new page
        const page = await browser.newPage();
        
        // Navigate to the URL
        await page.goto(url, { waitUntil: 'networkidle0' });
        
        // Get page title
        const title = await page.title();
        
        // Get page content
        const content = await page.content();
        
        // Take screenshot
        const screenshot = await page.screenshot({ encoding: 'base64' });
        
        // Close browser
        await browser.close();
        
        // Return response
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Successfully processed page',
                title: title,
                url: url,
                contentLength: content.length,
                screenshotSize: screenshot.length,
                screenshot: screenshot
            })
        };
    } catch (error) {
        console.error('Error:', error);
        
        // Ensure browser is closed in case of error
        if (browser) {
            await browser.close();
        }
        
        return {
            statusCode: 500,
            body: JSON.stringify({
                message: 'Error processing page',
                error: error.message
            })
        };
    }
}; 