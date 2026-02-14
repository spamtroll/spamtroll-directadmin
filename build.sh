#!/bin/bash
#
# Build script for Spamtroll DirectAdmin Plugin
#
# Creates a plugin.tar.gz file that can be installed in DirectAdmin.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PLUGIN_NAME="spamtroll"

echo "Building Spamtroll DirectAdmin Plugin..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$PLUGIN_NAME"

# Copy plugin files
cp -r "$SCRIPT_DIR/admin" "$BUILD_DIR/$PLUGIN_NAME/"
cp -r "$SCRIPT_DIR/hooks" "$BUILD_DIR/$PLUGIN_NAME/"
cp -r "$SCRIPT_DIR/scripts" "$BUILD_DIR/$PLUGIN_NAME/"
cp -r "$SCRIPT_DIR/exim" "$BUILD_DIR/$PLUGIN_NAME/"
cp -r "$SCRIPT_DIR/lib" "$BUILD_DIR/$PLUGIN_NAME/"
cp -r "$SCRIPT_DIR/images" "$BUILD_DIR/$PLUGIN_NAME/"
cp "$SCRIPT_DIR/plugin.conf" "$BUILD_DIR/$PLUGIN_NAME/"

# Create data directory structure
mkdir -p "$BUILD_DIR/$PLUGIN_NAME/data/cache"

# Remove dev files from distribution
rm -f "$BUILD_DIR/$PLUGIN_NAME/CLAUDE.md"

# Ensure scripts are executable
chmod +x "$BUILD_DIR/$PLUGIN_NAME/scripts/"*.sh
chmod +x "$BUILD_DIR/$PLUGIN_NAME/exim/spamtroll-check"
chmod 755 "$BUILD_DIR/$PLUGIN_NAME/admin/index.html"

# Create tarball
cd "$BUILD_DIR"
tar -czvf plugin.tar.gz "$PLUGIN_NAME"

# Move to parent directory
mv plugin.tar.gz "$SCRIPT_DIR/"

# Clean up
rm -rf "$BUILD_DIR"

echo ""
echo "Build complete!"
echo "Output: $SCRIPT_DIR/plugin.tar.gz"
echo ""
echo "To install in DirectAdmin:"
echo "1. Upload plugin.tar.gz to your server"
echo "2. Go to DirectAdmin > Plugin Manager"
echo "3. Click 'Upload Plugin' and select the file"
echo ""
