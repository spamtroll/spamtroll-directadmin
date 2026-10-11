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
cp "$SCRIPT_DIR/LICENSE" "$SCRIPT_DIR/README.md" "$SCRIPT_DIR/CHANGELOG.md" "$BUILD_DIR/$PLUGIN_NAME/"
cp "$SCRIPT_DIR/PRODUCTION-AUDIT-2026-10-11.md" "$BUILD_DIR/$PLUGIN_NAME/"

# The installer creates data/cache. Never ship these directories: native
# updates extract over the existing plugin and could replace their owner
# or permissions, making the saved API key unreadable by Exim.

# Remove dev files from distribution
rm -f "$BUILD_DIR/$PLUGIN_NAME/CLAUDE.md"

# Ensure scripts are executable
chmod +x "$BUILD_DIR/$PLUGIN_NAME/scripts/"*.sh
chmod +x "$BUILD_DIR/$PLUGIN_NAME/exim/spamtroll-check"
chmod 755 "$BUILD_DIR/$PLUGIN_NAME/admin/index.html"

# DirectAdmin extracts directly INTO the plugin directory. A spamtroll/
# wrapper silently installs a nested copy and leaves the old version and
# lifecycle scripts active. Keep plugin.conf and scripts/ at archive root.
cd "$BUILD_DIR/$PLUGIN_NAME"
if tar --version | head -1 | grep -q bsdtar; then
    TAR_OWNERS=(--uid 0 --gid 0 --uname root --gname root)
else
    TAR_OWNERS=(--owner=0 --group=0)
fi
COPYFILE_DISABLE=1 tar "${TAR_OWNERS[@]}" -czvf "$BUILD_DIR/plugin.tar.gz" \
    admin hooks scripts exim lib images plugin.conf LICENSE README.md CHANGELOG.md \
    PRODUCTION-AUDIT-2026-10-11.md

# Move to parent directory
mv "$BUILD_DIR/plugin.tar.gz" "$SCRIPT_DIR/"

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
