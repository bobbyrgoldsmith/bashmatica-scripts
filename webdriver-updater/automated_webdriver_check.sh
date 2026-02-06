#!/bin/bash

BROWSER_TYPE="${1:-chrome}"
DRIVER_DIR="/opt/webdrivers"

get_chrome_version() {
    google-chrome --version | grep -oP '\d+\.\d+\.\d+' | head -1
}

get_firefox_version() {
    firefox --version | grep -oP '\d+\.\d+' | head -1
}

get_edge_version() {
    microsoft-edge --version | grep -oP '\d+\.\d+\.\d+' | head -1
}

update_chromedriver() {
    local version=$(get_chrome_version)
    local major=$(echo "$version" | cut -d. -f1)

    # Chrome 115+ uses the new Chrome for Testing endpoints
    if [ "$major" -ge 115 ]; then
        local driver_version=$(curl -s "https://googlechromelabs.github.io/chrome-for-testing/LATEST_RELEASE_${version%.*}")
        local driver_url="https://storage.googleapis.com/chrome-for-testing-public/${driver_version}/linux64/chromedriver-linux64.zip"
    else
        local driver_version=$(curl -s "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_${major}")
        local driver_url="https://chromedriver.storage.googleapis.com/${driver_version}/chromedriver_linux64.zip"
    fi

    curl -sL "$driver_url" -o /tmp/chromedriver.zip
    unzip -o /tmp/chromedriver.zip -d /tmp/
    # Handle both old and new zip structures
    mv /tmp/chromedriver-linux64/chromedriver "$DRIVER_DIR/chromedriver" 2>/dev/null \
        || mv /tmp/chromedriver "$DRIVER_DIR/chromedriver"
    chmod +x "$DRIVER_DIR/chromedriver"
    rm -rf /tmp/chromedriver*
}

update_geckodriver() {
    local latest=$(curl -s https://api.github.com/repos/mozilla/geckodriver/releases/latest \
        | grep -oP '"tag_name": "\K[^"]+')
    curl -sL "https://github.com/mozilla/geckodriver/releases/download/${latest}/geckodriver-${latest}-linux64.tar.gz" \
        -o /tmp/geckodriver.tar.gz
    tar -xzf /tmp/geckodriver.tar.gz -C "$DRIVER_DIR"
    chmod +x "$DRIVER_DIR/geckodriver"
    rm /tmp/geckodriver.tar.gz
}

update_edgedriver() {
    local version=$(get_edge_version)
    curl -sL "https://msedgedriver.azureedge.net/${version}/edgedriver_linux64.zip" \
        -o /tmp/edgedriver.zip
    unzip -o /tmp/edgedriver.zip -d "$DRIVER_DIR"
    chmod +x "$DRIVER_DIR/msedgedriver"
    rm /tmp/edgedriver.zip
}

case "$BROWSER_TYPE" in
    chrome)  update_chromedriver ;;
    firefox) update_geckodriver ;;
    edge)    update_edgedriver ;;
    *)       echo "Unknown browser: $BROWSER_TYPE"; exit 1 ;;
esac

echo "Updated $BROWSER_TYPE driver successfully"