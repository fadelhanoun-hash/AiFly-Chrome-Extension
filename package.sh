#!/bin/bash

# AiFly Chrome Extension Packaging Script
# This script creates a properly formatted zip file for Chrome Web Store submission

echo "📦 AiFly Packaging Script"
echo "=========================="
echo ""

# Get the current directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_NAME="AiFly"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${SCRIPT_DIR}/${PROJECT_NAME}_${TIMESTAMP}.zip"
TEMP_DIR="${SCRIPT_DIR}/.temp_package"

echo "📁 Project directory: $SCRIPT_DIR"
echo "📦 Output file: $OUTPUT_FILE"
echo ""

# Clean up any previous temp directory
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi

# Create temp directory and copy files
mkdir -p "$TEMP_DIR"

echo "⏳ Copying extension files..."

# Copy all necessary files, excluding unnecessary ones
cp manifest.json "$TEMP_DIR/"
cp background.js "$TEMP_DIR/"
cp content.js "$TEMP_DIR/"
cp options.html "$TEMP_DIR/"
cp options.js "$TEMP_DIR/"
cp messenger.css "$TEMP_DIR/"

# Copy icons
cp -r icons "$TEMP_DIR/"

# Copy markdown files for reference
cp README.md "$TEMP_DIR/"
cp PRIVACY_POLICY.md "$TEMP_DIR/"
cp STORE_LISTING.md "$TEMP_DIR/"

echo "✅ Files copied successfully"
echo ""

# Create the zip file
echo "⏳ Creating zip archive..."
cd "$TEMP_DIR"
zip -q -r "$OUTPUT_FILE" . 2>&1
cd "$SCRIPT_DIR"

# Check if zip was created successfully
if [ -f "$OUTPUT_FILE" ]; then
    FILE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')
    echo "✅ Zip file created successfully!"
    echo ""
    echo "📊 Package Information:"
    echo "  Filename: $(basename "$OUTPUT_FILE")"
    echo "  Size: $FILE_SIZE"
    echo "  Location: $OUTPUT_FILE"
    echo ""
    echo "📋 Package Contents:"
    echo "  ✓ manifest.json"
    echo "  ✓ background.js"
    echo "  ✓ content.js"
    echo "  ✓ options.html"
    echo "  ✓ options.js"
    echo "  ✓ messenger.css"
    echo "  ✓ icons/ (icon-16.png, icon-48.png, icon-128.png)"
    echo "  ✓ README.md"
    echo "  ✓ PRIVACY_POLICY.md"
    echo "  ✓ STORE_LISTING.md"
    echo ""
    echo "✨ Ready for Chrome Web Store submission!"
    echo ""
    echo "Next steps:"
    echo "1. Go to https://chrome.google.com/webstore/devcenter"
    echo "2. Sign in with your Google account"
    echo "3. Click 'Create new item'"
    echo "4. Upload the zip file: $OUTPUT_FILE"
    echo "5. Fill in the store listing details"
    echo "6. Submit for review"
else
    echo "❌ Error: Failed to create zip file"
    exit 1
fi

# Cleanup temp directory
rm -rf "$TEMP_DIR"

exit 0
