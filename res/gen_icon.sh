#!/bin/bash
set -e

# Step 1: Generate PNGs from SVG
for size in 16 32 48 64 128 256 512 1024; do
  # inkscape -z -o $size.png -w $size -h $size icon.svg
  magick icon.png -resize ${size}x${size} app_icon_$size.png
  magick icon.png -resize ${size}x${size} $size.png
done

# Step 2: Generate .ico (Windows)
magick 16.png 32.png 48.png 128.png 256.png -colors 256 icon.ico

# Step 3: Create iconset folder for macOS
ICONSET="AppIcon.iconset"
mkdir -p $ICONSET

# Step 4: Copy PNGs to correct iconset filenames
cp 16.png       $ICONSET/icon_16x16.png
cp 32.png       $ICONSET/icon_16x16@2x.png
cp 32.png       $ICONSET/icon_32x32.png
cp 64.png       $ICONSET/icon_32x32@2x.png
cp 128.png      $ICONSET/icon_128x128.png
cp 256.png      $ICONSET/icon_128x128@2x.png
cp 256.png      $ICONSET/icon_256x256.png
cp 512.png      $ICONSET/icon_256x256@2x.png
cp 512.png      $ICONSET/icon_512x512.png
cp 1024.png     $ICONSET/icon_512x512@2x.png

# Step 5: Generate .icns
iconutil -c icns $ICONSET

cp icon.ico tray-ico.ico
cp 512.png mac-icon.png
cp 32.png mac-tray-dark-x2.png
cp 32.png mac-tray-light-x2.png

# Step 6: Cleanup temporary files
rm -rf 16.png 32.png 48.png 64.png 128.png 256.png 512.png 1024.png $ICONSET


echo "✅ icon.ico and AppIcon.icns generated!"
