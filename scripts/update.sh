#!/bin/bash
#
# Spamtroll DirectAdmin Plugin Update Script
#
# This script is called by DirectAdmin when the plugin is updated.
# It updates the check script and ACL while preserving user configuration.
#

set -e

# Paths
PLUGIN_DIR="/usr/local/directadmin/plugins/spamtroll"
EXIM_ACL_FILE="/etc/exim.acl_check_message.pre.conf"
SPAMTROLL_BIN="/usr/local/bin/spamtroll-check"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Spamtroll DirectAdmin Plugin Updater"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Update spamtroll-check script
echo "Updating spamtroll-check script..."
if [[ -f "$PLUGIN_DIR/exim/spamtroll-check" ]]; then
    cp "$PLUGIN_DIR/exim/spamtroll-check" "$SPAMTROLL_BIN"
    chmod 755 "$SPAMTROLL_BIN"
    chown root:root "$SPAMTROLL_BIN"
    echo -e "${GREEN}Updated: $SPAMTROLL_BIN${NC}"
else
    echo -e "${YELLOW}Warning: Source file not found, skipping${NC}"
fi

# Update Exim ACL
echo ""
echo "Updating Exim ACL configuration..."
if [[ -f "$PLUGIN_DIR/exim/acl_check_message.pre.conf" ]]; then
    # Backup existing ACL
    if [[ -f "$EXIM_ACL_FILE" ]]; then
        BACKUP_FILE="${EXIM_ACL_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$EXIM_ACL_FILE" "$BACKUP_FILE"
        echo -e "${YELLOW}Backed up existing ACL to: $BACKUP_FILE${NC}"
    fi
    cp "$PLUGIN_DIR/exim/acl_check_message.pre.conf" "$EXIM_ACL_FILE"
    chmod 644 "$EXIM_ACL_FILE"
    echo -e "${GREEN}Updated: $EXIM_ACL_FILE${NC}"
else
    echo -e "${YELLOW}Warning: Source file not found, skipping${NC}"
fi

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
echo -e "${GREEN}Update complete!${NC}"
echo ""
echo "Your configuration has been preserved."
echo ""

exit 0
