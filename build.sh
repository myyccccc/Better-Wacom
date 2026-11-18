#!/bin/zsh
# 编译并打包成 Better Wacom.app（放在 build/ 下）
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

# 图标
if [[ ! -f build/AppIcon.icns || scripts/make_icon.swift -nt build/AppIcon.icns ]]; then
    mkdir -p build
    swift scripts/make_icon.swift build/AppIcon.iconset >/dev/null
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
    rm -rf build/AppIcon.iconset
fi

# 打包到本机磁盘的固定位置：T7（非 APFS）会生成 ._ 文件导致签名失败；路径固定，辅助功能授权才会一直有效
APP="$HOME/Applications/Better Wacom.app"
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BetterWacom "$APP/Contents/MacOS/BetterWacom"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# 多语言
for d in Resources/Localization/*.lproj(N); do cp -R "$d" "$APP/Contents/Resources/"; done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>zh-Hans</string><string>en</string><string>zh-Hant</string><string>ja</string><string>ko</string>
        <string>es</string><string>es-419</string><string>fr</string><string>de</string><string>pt-BR</string>
        <string>pt-PT</string><string>it</string><string>nl</string><string>ru</string><string>ar</string>
    </array>
    <key>CFBundleIdentifier</key><string>com.denis.BetterWacom</string>
    <key>CFBundleName</key><string>Better Wacom</string>
    <key>CFBundleDisplayName</key><string>Better Wacom</string>
    <key>CFBundleExecutable</key><string>BetterWacom</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Denis Chen</string>
</dict>
</plist>
PLIST
# 签名：优先用钥匙串里的 Developer ID（身份稳定，辅助功能授权不会因重新编译失效）；
# 没有证书（例如别人从源码编译）时退回本机临时签名，每次重新编译后可能要重新授权。
# 可用环境变量 SIGN_ID 指定证书。
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Developer ID Application/ {print $2; exit}')}"
if [[ -n "$SIGN_ID" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
    echo "未找到 Developer ID 证书，使用临时签名（ad-hoc）"
    codesign --force --sign - "$APP"
fi
rm -rf "build/Better Wacom.app"
echo "已生成 $APP"
# 重启到新版本：已登记开机自启动就交给 launchd 重启（-k 先结束旧进程），否则直接打开（首次打开时会自己登记）
# 先结束所有旧进程：手动 open 打开的实例不归 launchd 管，kickstart -k 杀不掉它，旧版会一直跑着
pkill -f "Better Wacom.app/Contents/MacOS/BetterWacom" || true
sleep 1
if launchctl print "gui/$(id -u)/com.denis.BetterWacom" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/com.denis.BetterWacom"
else
    open "$APP"
fi
