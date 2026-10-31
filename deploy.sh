#!/bin/bash
# Mac Shield deploy script
#
# Usage:
#   ./deploy.sh                                   # ad-hoc signing (works for anyone)
#   SIGN_IDENTITY="ShadowAgentCert" ./deploy.sh  # stable signing (keeps permissions)
set -eu

APP_NAME="ShadowAgent.app"
LABEL="com.ph4ntom.shadow.ShadowAgent"
PLIST_NAME="${LABEL}.plist"
USER_LAUNCHAGENTS="$HOME/Library/LaunchAgents"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
USER_ID=$(id -u)

cd "$(dirname "$0")"

# ---------- 1. Checks before we start ----------
if [ ! -f "ShadowAgent/Secrets.swift" ]; then
    echo " ShadowAgent/Secrets.swift is missing."
    echo "   Run: cp ShadowAgent/Secrets.swift.example ShadowAgent/Secrets.swift"
    echo "   Then fill in your Firebase values."
    exit 1
fi

if [ "$SIGN_IDENTITY" != "-" ]; then
    if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
        echo " Signing certificate \"$SIGN_IDENTITY\" was not found."
        echo "   See the signing section of docs/TCC_PERMISSIONS.md to create it."
        exit 1
    fi
    echo " Signing with stable identity: $SIGN_IDENTITY"
else
    echo "  Using ad-hoc signing. macOS may ask for permissions again after each deploy."
fi

# ---------- 2. Stop the old copy first ----------
echo " Stopping any running copy..."
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
sleep 1

# ---------- 3. Build ----------
echo " Building Release..."
xcodebuild -project ShadowAgent.xcodeproj -scheme ShadowAgent \
    -configuration Release -derivedDataPath ./build build

BUILT_APP=$(find ./build -name "${APP_NAME}" -type d | head -n 1)
if [ -z "$BUILT_APP" ]; then
    echo " Could not find the built ${APP_NAME}"
    exit 1
fi

# ---------- 4. Install and sign ----------
echo " Installing to /Applications..."
rm -rf "/Applications/${APP_NAME}"
cp -R "${BUILT_APP}" "/Applications/"

echo "Signing..."
codesign --force --deep --sign "$SIGN_IDENTITY" "/Applications/${APP_NAME}"

# ---------- 5. Install the LaunchAgent plist ----------
echo "  Installing LaunchAgent plist..."
mkdir -p "${USER_LAUNCHAGENTS}"
cp -f "${PLIST_NAME}" "${USER_LAUNCHAGENTS}/${PLIST_NAME}"
chown "$(whoami)" "${USER_LAUNCHAGENTS}/${PLIST_NAME}"
chmod 644 "${USER_LAUNCHAGENTS}/${PLIST_NAME}"
xattr -c "${USER_LAUNCHAGENTS}/${PLIST_NAME}"

# ---------- 6. Start the service ----------
echo " Starting service..."
launchctl enable "gui/${USER_ID}/${LABEL}"
launchctl bootstrap "gui/${USER_ID}" "${USER_LAUNCHAGENTS}/${PLIST_NAME}"

rm -rf ./build

# ---------- 7. Check that it is really running ----------
sleep 3
if pgrep -fl "${APP_NAME}" >/dev/null; then
    echo " Deployment complete! ShadowAgent is running."
    pgrep -fl "${APP_NAME}"
else
    echo "  Deployed, but ShadowAgent is not running."
    echo "   Check: tail -30 ~/Library/Logs/ShadowAgent/agent.log"
    echo "   Check: tail -30 /tmp/ShadowAgent.err.log"
    exit 1
fi