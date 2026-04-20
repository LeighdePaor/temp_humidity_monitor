#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing prerequisites"
sudo apt-get update
sudo apt-get install -y curl jq tar gzip

echo "==> Fetching latest PowerShell release metadata"
RELEASE_JSON=/tmp/powershell-release.json
curl -fsSL https://api.github.com/repos/PowerShell/PowerShell/releases/latest -o "$RELEASE_JSON"

PS_VERSION=$(jq -r '.tag_name | ltrimstr("v")' "$RELEASE_JSON" | tr -d '\r\n')
ARCH=$(dpkg --print-architecture)
KERNEL_ARCH=$(uname -m)

echo "Detected Debian architecture: $ARCH"
echo "Detected kernel architecture: $KERNEL_ARCH"

if [ "$ARCH" = "armhf" ] && [ "$KERNEL_ARCH" != "armv7l" ]; then
  echo "Warning: armhf userspace detected, but kernel reports $KERNEL_ARCH"
fi

case "$ARCH" in
  arm64)
    ASSET_PATTERN='linux-arm64\\.tar\\.gz$'
    ;;
  armhf)
    ASSET_PATTERN='linux-arm32\\.tar\\.gz$'
    ;;
  *)
    echo "Unsupported architecture for this quickstart: $ARCH"
    rm -f "$RELEASE_JSON"
    exit 1
    ;;
esac

TARBALL_URL=$(jq -r ".assets[] | select(.name | test(\"${ASSET_PATTERN}\")) | .browser_download_url" "$RELEASE_JSON" | head -n1)

if [ -z "$PS_VERSION" ] || [ -z "$TARBALL_URL" ]; then
  echo "Failed to resolve PowerShell tarball URL from GitHub API for arch: $ARCH"
  rm -f "$RELEASE_JSON"
  exit 1
fi

echo "Resolved PowerShell version: $PS_VERSION"
echo "Downloading: $TARBALL_URL"
curl -fL --retry 5 --retry-delay 2 --retry-all-errors "$TARBALL_URL" -o /tmp/powershell.tar.gz

echo "==> Installing pwsh"
sudo rm -rf /opt/microsoft/powershell/7
sudo rm -f /usr/bin/pwsh
sudo mkdir -p /opt/microsoft/powershell/7
sudo tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7
sudo chmod +x /opt/microsoft/powershell/7/pwsh
sudo ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh

echo "==> Registering pwsh as a valid login shell"
if ! grep -qxF "/usr/bin/pwsh" /etc/shells; then
  echo "/usr/bin/pwsh" | sudo tee -a /etc/shells >/dev/null
fi

echo "Installed pwsh binary info:"
file /opt/microsoft/powershell/7/pwsh

if [ "$ARCH" = "armhf" ] && ! file /opt/microsoft/powershell/7/pwsh | grep -qi "ARM"; then
  echo "Installed pwsh binary does not look like ARM32."
  exit 1
fi

if [ "$ARCH" = "arm64" ] && ! file /opt/microsoft/powershell/7/pwsh | grep -qi "aarch64\|ARM aarch64"; then
  echo "Installed pwsh binary does not look like ARM64."
  exit 1
fi

rm -f /tmp/powershell.tar.gz "$RELEASE_JSON"

echo "==> PowerShell installation complete"
echo "Run: pwsh --version"
