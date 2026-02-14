#!/bin/bash
#
# Spamtroll DirectAdmin Plugin Uninstaller
#
# This script is called by DirectAdmin when the plugin is uninstalled.
# It removes all Spamtroll components and restores Exim to normal operation.
#
# What it removes:
# - /usr/local/bin/spamtroll-check
# - /etc/exim.acl_check_message.pre.conf
#
# What it keeps (for potential reinstall):
# - Plugin data directory with spamtroll.conf (your settings)
# - /var/log/spamtroll.log (your logs)
#

set -e

# Paths
PLUGIN_DIR="/usr/local/directadmin/plugins/spamtroll"
DATA_DIR="$PLUGIN_DIR/data"
CONFIG_FILE="$DATA_DIR/spamtroll.conf"
EXIM_ACL_FILE="/etc/exim.acl_check_message.pre.conf"
SPAMTROLL_BIN="/usr/local/bin/spamtroll-check"
LOG_FILE="/var/log/spamtroll.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Spamtroll DirectAdmin Plugin Uninstaller"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Remove spamtroll-check script
echo "Removing spamtroll-check script..."
if [[ -f "$SPAMTROLL_BIN" ]]; then
    rm -f "$SPAMTROLL_BIN"
    echo -e "${GREEN}Removed: $SPAMTROLL_BIN${NC}"
else
    echo -e "${YELLOW}Not found: $SPAMTROLL_BIN (skipping)${NC}"
fi

# Remove Exim ACL
echo ""
echo "Removing Exim ACL configuration..."
if [[ -f "$EXIM_ACL_FILE" ]]; then
    # Check if this is our ACL file
    if grep -q "Spamtroll" "$EXIM_ACL_FILE" 2>/dev/null; then
        rm -f "$EXIM_ACL_FILE"
        echo -e "${GREEN}Removed: $EXIM_ACL_FILE${NC}"
    else
        echo -e "${YELLOW}Warning: ACL file exists but was modified. Keeping for safety.${NC}"
    fi
else
    echo -e "${YELLOW}Not found: $EXIM_ACL_FILE (skipping)${NC}"
fi

# Keep config and logs
echo ""
echo -e "${YELLOW}Keeping configuration and logs for potential reinstall:${NC}"
echo "  - $CONFIG_FILE"
echo "  - $LOG_FILE"
echo ""
echo "To remove these files manually, run:"
echo "  rm -f $CONFIG_FILE $LOG_FILE"
echo "  rm -rf $DATA_DIR"

# Rebuild Exim configuration via DirectAdmin
echo ""
echo "Rebuilding Exim configuration..."
if [[ -x /usr/local/directadmin/directadmin ]]; then
    cd /usr/local/directadmin && ./directadmin build exim_conf 2>&1
    echo -e "${GREEN}Exim configuration rebuilt successfully${NC}"
else
    # Fallback for non-standard DA installations
    if systemctl restart exim 2>/dev/null; then
        echo -e "${GREEN}Exim restarted successfully${NC}"
    elif service exim restart 2>/dev/null; then
        echo -e "${GREEN}Exim restarted successfully${NC}"
    else
        echo -e "${YELLOW}Warning: Could not rebuild Exim config. Please run: cd /usr/local/directadmin && ./directadmin build exim_conf${NC}"
    fi
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Uninstallation complete!${NC}"
echo "=========================================="
echo ""
echo "Spamtroll has been removed from your system."
echo "Email filtering is now disabled."
echo ""

exit 0
