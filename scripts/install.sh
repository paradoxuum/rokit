#!/bin/sh

BINARY_NAME="rokit"
REPOSITORY="filiptibell/rokit"

# Make sure we have prerequisites installed: curl + unzip
if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: 'curl' is not installed." >&2
    exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
    echo "ERROR: 'unzip' is not installed." >&2
    exit 1
fi

# Determine OS and architecture for the current system
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$OS" in
    darwin) OS="macos" ;;
    linux) OS="linux" ;;
    cygwin*|mingw*|msys*) OS="windows" ;;
    *)
        echo "Unsupported OS: $OS" >&2
        exit 1 ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    x86-64) ARCH="x86_64" ;;
    arm64) ARCH="aarch64" ;;
    aarch64) ARCH="aarch64" ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2;
        exit 1 ;;
esac

if [ ! -z "$GITHUB_PAT" ]; then
    echo "NOTE: Using provided GITHUB_PAT for authentication"
fi

# Construct file pattern for our desired zip file based on OS + arch
# NOTE: This only works for exact patterns "binary-X.Y.Z-os-arch.zip"
# and WILL break if the version contains extra metadata / pre-release
VERSION_PATTERN="[0-9]*\\.[0-9]*\\.[0-9]*"
API_URL="https://api.github.com/repos/$REPOSITORY/releases/latest"
if [ ! -z "$1" ]; then
    # Fetch a specific version from given script argument
    VERSION_PATTERN="$1"
    API_URL="https://api.github.com/repos/$REPOSITORY/releases/tags/v$1"
    echo "\n[1 / 3] Looking for $BINARY_NAME release with tag 'v$1'"
else
    # Fetch the latest release from the GitHub API
    echo "\n[1 / 3] Looking for latest $BINARY_NAME release"
fi
FILE_PATTERN="${BINARY_NAME}-${VERSION_PATTERN}-${OS}-${ARCH}.zip"

# Use curl to fetch the latest release data from GitHub API
if [ ! -z "$GITHUB_PAT" ]; then
    RELEASE_JSON_DATA=$(curl --proto '=https' --tlsv1.2 -sSf "$API_URL" -H "Authorization: token $GITHUB_PAT")
else
    RELEASE_JSON_DATA=$(curl --proto '=https' --tlsv1.2 -sSf "$API_URL")
fi

# Check if the release was fetched successfully
if [ -z "$RELEASE_JSON_DATA" ] || echo "$RELEASE_JSON_DATA" | grep -q "Not Found"; then
    echo "ERROR: Latest release was not found. Please check your network connection." >&2
    exit 1
fi


# Try to extract the asset url from the response by searching for a
# matching asset name, and then picking the "url" that came before it
read RELEASE_ASSET_ID RELEASE_ASSET_NAME <<EOF
$(echo "$RELEASE_JSON_DATA" | awk -v repo="$REPOSITORY" -v pattern="$FILE_PATTERN" '
  /"url":/ && $0 ~ "https://api.github.com/repos/" repo "/releases/assets/" {
    gsub(/.*\/releases\/assets\/|\"|,/, "", $0)
    asset_number=$0
  }
  /"name":/ && asset_number && $0 ~ pattern {
    # Remove quotes and trailing comma for clean output
    gsub(/\"|,/, "", $2)
    print asset_number, $2
    exit
  }
')
EOF
if [ -z "$RELEASE_ASSET_ID" ]; then
    echo "ERROR: Failed to find asset that matches the pattern \"$FILE_PATTERN\" in the latest release." >&2
    exit 1
fi

# Download the file using curl and make sure it was successful
echo "[2 / 3] Downloading '$RELEASE_ASSET_NAME'"
RELEASE_DOWNLOAD_URL="https://api.github.com/repos/$REPOSITORY/releases/assets/$RELEASE_ASSET_ID"
ZIP_FILE=$(echo "$RELEASE_DOWNLOAD_URL" | rev | cut -d '/' -f 1 | rev)
if [ ! -z "$GITHUB_PAT" ]; then
    curl --proto '=https' --tlsv1.2 -L -o "$ZIP_FILE" -sSf "$RELEASE_DOWNLOAD_URL" -H "Accept: application/octet-stream"  -H "Authorization: token $GITHUB_PAT"
else
    curl --proto '=https' --tlsv1.2 -L -o "$ZIP_FILE" -sSf "$RELEASE_DOWNLOAD_URL" -H "Accept: application/octet-stream"
fi
if [ ! -f "$ZIP_FILE" ]; then
    echo "ERROR: Failed to download the release archive '$ZIP_FILE'." >&2
    exit 1
fi

# Unzip only the specific file we want and make sure it was successful
unzip -o -q "$ZIP_FILE" "$BINARY_NAME" -d .
rm "$ZIP_FILE"
if [ ! -f "$BINARY_NAME" ]; then
    echo "ERROR: The file '$BINARY_NAME' does not exist in the downloaded archive." >&2
    exit 1
fi

# Execute the file and remove it when done
echo "[3 / 3] Running $BINARY_NAME installation\n"
chmod +x "$BINARY_NAME"
./"$BINARY_NAME" self-install
rm "$BINARY_NAME"
