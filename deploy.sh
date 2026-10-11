#!/bin/bash
set -e

APP_NAME="ShadowAgent.app"
PLIST_NAME="com.ph4ntom.shadow.ShadowAgent.plist"
USER_LAUNCHAGENTS="$HOME/Library/LaunchAgents"

echo "Building Production Xcode Release..."
xcodebuild -project ShadowAgent.xcodeproj -scheme ShadowAgent -configuration Release -derivedDataPath ./build build

BUILT_APP=$(find ./build -name "${APP_NAME}" -type d | head -n 1)

if [ -z "$BUILT_APP" ]; then
    echo " Error: Could not find built ${APP_NAME}"
    exit 1
fi

echo " Installing ${APP_NAME} to /Applications..."
rm -rf "/Applications/${APP_NAME}"
cp -R "${BUILT_APP}" "/Applications/"

echo " Applying ad-hoc signature..."
codesign --force --deep --sign - "/Applications/${APP_NAME}"

echo " Syncing LaunchAgent plist and clearing attributes..."
mkdir -p "${USER_LAUNCHAGENTS}"
cp -f "${PLIST_NAME}" "${USER_LAUNCHAGENTS}/${PLIST_NAME}"
chown $(whoami) "${USER_LAUNCHAGENTS}/${PLIST_NAME}"
chmod 644 "${USER_LAUNCHAGENTS}/${PLIST_NAME}"
xattr -c "${USER_LAUNCHAGENTS}/${PLIST_NAME}"

echo " Reloading LaunchAgent service..."
launchctl enable gui/$(id -u)/com.ph4ntom.shadow.ShadowAgent
launchctl bootout gui/$(id -u) "${USER_LAUNCHAGENTS}/${PLIST_NAME}" 2>/dev/null || true
launchctl bootstrap gui/$(id -u) "${USER_LAUNCHAGENTS}/${PLIST_NAME}"

rm -rf ./build

echo " Deployment complete! ShadowAgent is active."
