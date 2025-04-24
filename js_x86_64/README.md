# Chrome Lambda Function

This project provides a Node.js-based AWS Lambda function that uses Puppeteer for browser automation.

## Project Structure

```
.
├── deploy.sh
├── index.js
├── package.json
└── README.md
```

## Prerequisites

- Node.js 14.x or higher
- AWS CLI configured with appropriate credentials
- AWS Lambda permissions

## Quick Start

1. Install dependencies:
   ```bash
   npm install
   ```

2. Deploy the Lambda function:
   ```bash
   chmod +x deploy.sh && ./deploy.sh
   ```

The deployment script will:
- Create a deployment package with necessary files
- Upload the package to S3
- Update the Lambda function with the new code

## Function Details

The Lambda function:
1. Launches Chrome in headless mode
2. Navigates to the specified URL (or example.com by default)
3. Takes a screenshot
4. Retrieves the page title and content
5. Returns a JSON response with:
   - Page title
   - URL
   - Content length
   - Screenshot size

## Configuration

The Lambda function requires:
- Runtime: Node.js 14.x or higher
- Memory: At least 1024 MB
- Timeout: At least 30 seconds
- Environment variables: None required

## Troubleshooting

If you encounter issues:

1. Check your AWS credentials are properly configured
2. Verify you have the necessary AWS Lambda permissions
3. Ensure your Node.js version is compatible (14.x or higher)
4. Check the Lambda function logs in AWS CloudWatch

## Notes

- The function uses Puppeteer for browser automation
- Screenshots are returned in base64 format
- The deployment package is uploaded to S3 to handle size limitations
- Make sure to configure appropriate memory and timeout settings for your Lambda function 