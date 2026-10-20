#!/usr/bin/env bash
# Renders every platform's launcher icon from assets/icon.
# Needs rsvg-convert and ImageMagick: brew install librsvg imagemagick
set -euo pipefail
cd "$(dirname "$0")/.."

graphite='#1D1D1B'
note=$(sed '1d;$d' assets/icon/note.svg)
monochrome=$(sed '1d;$d' assets/icon/note-monochrome.svg)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

svg() {
  printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">%s</svg>' "$2" >"$tmp/$1.svg"
}
scaled() {
  printf '<g transform="translate(512 512) scale(%s) translate(-512 -512)">%s</g>' "$1" "$2"
}
png() {
  rsvg-convert -w "$2" -h "$2" "$tmp/$1.svg" -o "$3"
}
times() {
  awk "BEGIN { print $1 * $2 }"
}

plate="<rect width='1024' height='1024' rx='229' fill='$graphite'/>$note"
svg square "<rect width='1024' height='1024' fill='$graphite'/>$note"
svg rounded "$plate"
# Apple's grid: an 824 px plate on a 1024 px canvas, with a soft shadow.
svg macos "<filter id='blur'><feGaussianBlur stdDeviation='10'/></filter><rect x='100' y='110' width='824' height='824' rx='184' fill-opacity='.3' filter='url(#blur)'/>$(scaled .8047 "$plate")"
# Launchers show the middle 72 dp of the 108 dp adaptive layers.
svg foreground "$(scaled .6667 "$note")"
svg monochrome "$(scaled .6667 "$monochrome")"
# Maskable icons keep what matters inside the middle 80%.
svg maskable "<rect width='1024' height='1024' fill='$graphite'/>$(scaled .9 "$note")"
# Drawn on a 16 px grid: the tilted note blurs at 16 and 32 px.
cp assets/icon/icon-small.svg "$tmp/small.svg"

ios=ios/Runner/Assets.xcassets/AppIcon.appiconset
for file in "$ios"/Icon-App-*.png; do
  spec=${file##*Icon-App-}
  spec=${spec%.png}
  scale=${spec##*@}
  png square "$(times "${spec%%x*}" "${scale%x}")" "$file"
  # The App Store rejects icons with an alpha channel.
  magick "$file" -alpha off "PNG24:$file"
done

for size in 16 32; do
  png small "$size" "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png"
done
for size in 64 128 256 512 1024; do
  png macos "$size" "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png"
done

for density in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  res=android/app/src/main/res/mipmap-${density%%:*}
  factor=${density#*:}
  png rounded "$(times 48 "$factor")" "$res/ic_launcher.png"
  png foreground "$(times 108 "$factor")" "$res/ic_launcher_foreground.png"
  png monochrome "$(times 108 "$factor")" "$res/ic_launcher_monochrome.png"
done

png small 32 web/favicon.png
for size in 192 512; do
  png rounded "$size" "web/icons/Icon-$size.png"
  png maskable "$size" "web/icons/Icon-maskable-$size.png"
done

for size in 16 32; do
  png small "$size" "$tmp/windows-$size.png"
done
for size in 20 24 40 48 64 256; do
  png rounded "$size" "$tmp/windows-$size.png"
done
magick "$tmp"/windows-{16,20,24,32,40,48,64,256}.png windows/runner/resources/app_icon.ico
