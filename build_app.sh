#!/bin/bash
set -e
cd "$(dirname "$0")"

APP_NAME="Stopwatch"
BUNDLE_ID="com.${USER}.stopwatch"
APP="$APP_NAME.app"
WORK="$(mktemp -d)"

echo "==> Compiling"
swiftc -parse-as-library -O StopwatchApp.swift -o "$WORK/$APP_NAME"

echo "==> Drawing icon"
cat > "$WORK/icon.swift" <<'EOF'
import AppKit

let S = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background tile
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                        xRadius: 185, yRadius: 185)
NSGradient(starting: c(0x34374F), ending: c(0x15161F))!.draw(in: tile, angle: -90)

let cx: CGFloat = 512, cy: CGFloat = 470, r: CGFloat = 290

// Crown (top button) and stem
c(0x9AA0B4).setFill()
NSBezierPath(roundedRect: NSRect(x: cx - 55, y: cy + r + 10, width: 110, height: 60),
             xRadius: 14, yRadius: 14).fill()
NSBezierPath(rect: NSRect(x: cx - 26, y: cy + r - 10, width: 52, height: 30)).fill()

// Face and ring
c(0xF4F5F8).setFill()
NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
let ring = NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
ring.lineWidth = 34
c(0x3F72B5).setStroke()
ring.stroke()

// Tick marks
for i in 0..<60 {
    let a = CGFloat(i) * .pi / 30
    let major = i % 5 == 0
    let r1 = r - 36, r2 = r1 - (major ? 46 : 22)
    let p = NSBezierPath()
    p.move(to: NSPoint(x: cx + sin(a) * r1, y: cy + cos(a) * r1))
    p.line(to: NSPoint(x: cx + sin(a) * r2, y: cy + cos(a) * r2))
    p.lineWidth = major ? 12 : 5
    p.lineCapStyle = .round
    c(0x2B2D42).setStroke()
    p.stroke()
}

// Hand (pointing roughly to 2 o'clock)
let ha: CGFloat = .pi / 3
let hand = NSBezierPath()
hand.move(to: NSPoint(x: cx - sin(ha) * 40, y: cy - cos(ha) * 40))
hand.line(to: NSPoint(x: cx + sin(ha) * (r - 70), y: cy + cos(ha) * (r - 70)))
hand.lineWidth = 22
hand.lineCapStyle = .round
c(0xB5483F).setStroke()
hand.stroke()

// Center cap
c(0x2B2D42).setFill()
NSBezierPath(ovalIn: NSRect(x: cx - 30, y: cy - 30, width: 60, height: 60)).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
EOF
swiftc "$WORK/icon.swift" -o "$WORK/icon"
"$WORK/icon" "$WORK/icon_1024.png"

echo "==> Building iconset"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$WORK/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$WORK/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Installing to /Applications"
rm -rf "/Applications/$APP"
cp -R "$APP" /Applications/
touch "/Applications/$APP"
rm -rf "$WORK"

echo "Done. Launch it from Launchpad, Spotlight, or: open -a $APP_NAME"
