# WebDriver Auto-Updater

A browser-agnostic script that automatically updates Selenium WebDriver binaries to match installed browser versions. Designed to run as a pre-test step in CI pipelines.

From [Bashmatica! #1: The Hidden Maintenance Tax of Test Automation](https://newsletter.nodebridge.dev).

## The Problem

Browser auto-updates break Selenium test suites when the WebDriver binary version no longer matches the browser version:

```
SessionNotCreatedException: Message: session not created:
This version of ChromeDriver only supports Chrome version 114
Current browser version is 115.0.5790.102
```

This script eliminates that failure mode by checking and updating the driver before tests run.

## Supported Browsers

- Chrome (chromedriver)
- Firefox (geckodriver)
- Edge (msedgedriver)

## Usage

```bash
# Update chromedriver (default)
./automated_webdriver_check.sh

# Update geckodriver
./automated_webdriver_check.sh firefox

# Update msedgedriver
./automated_webdriver_check.sh edge
```

## Configuration

Edit these variables at the top of the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `BROWSER_TYPE` | `chrome` | Browser to update (chrome, firefox, edge) |
| `DRIVER_DIR` | `/opt/webdrivers` | Directory where driver binaries are stored |

## Requirements

- Linux (tested on Ubuntu 20.04+, Debian 11+)
- Bash 4.0+
- curl
- unzip (for Chrome and Edge)
- tar (for Firefox)
- GNU grep with Perl regex support (`grep -oP`)

The target browser must be installed for version detection to work.

## CI Integration

Add as a pre-test step in your pipeline:

**GitHub Actions:**
```yaml
- name: Update WebDriver
  run: ./automated_webdriver_check.sh chrome
```

**Jenkins:**
```groovy
stage('Update WebDriver') {
    steps {
        sh './automated_webdriver_check.sh chrome'
    }
}
```

**GitLab CI:**
```yaml
before_script:
  - ./automated_webdriver_check.sh chrome
```

## How It Works

1. Detects the installed browser version
2. Queries the appropriate API for the matching driver version
3. Downloads and extracts the driver binary
4. Sets executable permissions
5. Cleans up temporary files

For Chrome 115+, the script uses the newer Chrome for Testing endpoints. Earlier versions use the legacy chromedriver.storage.googleapis.com API.

## Limitations

- Linux only (uses GNU grep and Linux binary downloads)
- Assumes `DRIVER_DIR` exists and is writable
- No error handling for network failures or missing browsers
- Does not verify driver integrity (no checksum validation)

For production use, consider adding error handling, logging, and checksum verification.

## License

MIT License. See [LICENSE](../LICENSE) for details.
