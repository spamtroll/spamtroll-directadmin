#!/bin/bash
#
# Spamtroll DirectAdmin Plugin Installer
#
# This script is called by DirectAdmin when the plugin is installed.
# It sets up all necessary files and configurations for Spamtroll to work.
#
# What it does:
# 1. Installs the spamtroll-check script to /usr/local/bin/
# 2. Creates the Exim ACL configuration in /etc/exim.acl_check_message.pre.conf
# 3. Creates the config file in plugin data directory (if not exists)
# 4. Creates the log file /var/log/spamtroll.log
# 5. Restarts Exim to apply the ACL changes
#
# Requirements:
# - jq (for JSON parsing)
# - curl (for API calls)
#

set -e

# Paths
PLUGIN_DIR="/usr/local/directadmin/plugins/spamtroll"
EXIM_ACL_FILE="/etc/exim.acl_check_message.pre.conf"
SPAMTROLL_BIN="/usr/local/bin/spamtroll-check"
DATA_DIR="$PLUGIN_DIR/data"
CONFIG_FILE="$DATA_DIR/spamtroll.conf"
LOG_FILE="/var/log/spamtroll.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  Spamtroll DirectAdmin Plugin Installer"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    exit 1
fi

# Check for required tools
echo "Checking dependencies..."

if ! command -v curl &> /dev/null; then
    echo -e "${YELLOW}Warning: curl not found. Installing...${NC}"
    yum install -y curl 2>/dev/null || apt-get install -y curl 2>/dev/null || {
        echo -e "${RED}Error: Failed to install curl${NC}"
        exit 1
    }
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq not found. Installing...${NC}"
    yum install -y jq 2>/dev/null || apt-get install -y jq 2>/dev/null || {
        echo -e "${RED}Error: Failed to install jq${NC}"
        exit 1
    }
fi

echo -e "${GREEN}Dependencies OK${NC}"

# Install spamtroll-check script
echo ""
echo "Installing spamtroll-check script..."
if [[ -f "$PLUGIN_DIR/exim/spamtroll-check" ]]; then
    cp "$PLUGIN_DIR/exim/spamtroll-check" "$SPAMTROLL_BIN"
    chmod 755 "$SPAMTROLL_BIN"
    chown root:root "$SPAMTROLL_BIN"
    echo -e "${GREEN}Installed: $SPAMTROLL_BIN${NC}"
else
    echo -e "${RED}Error: spamtroll-check script not found in plugin directory${NC}"
    exit 1
fi

# Create data directory
echo ""
echo "Setting up data directory..."
mkdir -p "$DATA_DIR/cache"
chown -R diradmin:diradmin "$DATA_DIR"
chmod 770 "$DATA_DIR"
chmod 770 "$DATA_DIR/cache"
echo -e "${GREEN}Created: $DATA_DIR${NC}"

# Create config file (if not exists)
echo ""
echo "Setting up configuration..."
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<'CONF'
# Spamtroll Configuration
# Edit via DirectAdmin panel or manually here
#
# ENABLED: Set to "true" to enable spam filtering
# API_KEY: Your Spamtroll API key (get from https://spamtroll.io/dashboard)
# API_URL: Spamtroll API endpoint
# LOG_LEVEL: debug, info, or error
# TIMEOUT: API timeout in seconds

ENABLED=false
API_KEY=""
API_URL="https://api.spamtroll.io/api/v1/scan/check"
LOG_LEVEL="info"
TIMEOUT=5
CONF
    chmod 660 "$CONFIG_FILE"
    chown diradmin:diradmin "$CONFIG_FILE"
    echo -e "${GREEN}Created: $CONFIG_FILE${NC}"
else
    echo -e "${YELLOW}Config file already exists, keeping current settings${NC}"
fi

# Install Exim ACL
echo ""
echo "Configuring Exim ACL..."

# Backup existing ACL if present
if [[ -f "$EXIM_ACL_FILE" ]]; then
    BACKUP_FILE="${EXIM_ACL_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$EXIM_ACL_FILE" "$BACKUP_FILE"
    echo -e "${YELLOW}Backed up existing ACL to: $BACKUP_FILE${NC}"
fi

# Install new ACL
if [[ -f "$PLUGIN_DIR/exim/acl_check_message.pre.conf" ]]; then
    cp "$PLUGIN_DIR/exim/acl_check_message.pre.conf" "$EXIM_ACL_FILE"
    chmod 644 "$EXIM_ACL_FILE"
    chown root:root "$EXIM_ACL_FILE"
    echo -e "${GREEN}Installed: $EXIM_ACL_FILE${NC}"
else
    echo -e "${RED}Error: ACL config not found in plugin directory${NC}"
    exit 1
fi

# Create log file
echo ""
echo "Setting up log file..."
touch "$LOG_FILE"
chmod 640 "$LOG_FILE"
chown root:diradmin "$LOG_FILE"
echo -e "${GREEN}Created: $LOG_FILE${NC}"

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

# Verify installation
echo ""
echo "Verifying installation..."
ERRORS=0

if [[ ! -x "$SPAMTROLL_BIN" ]]; then
    echo -e "${RED}Error: $SPAMTROLL_BIN not executable${NC}"
    ((ERRORS++))
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: $CONFIG_FILE not found${NC}"
    ((ERRORS++))
fi

if [[ ! -f "$EXIM_ACL_FILE" ]]; then
    echo -e "${RED}Error: $EXIM_ACL_FILE not found${NC}"
    ((ERRORS++))
fi

if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}All components installed correctly${NC}"
else
    echo -e "${RED}Installation completed with $ERRORS errors${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Installation complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Go to DirectAdmin > Spamtroll"
echo "2. Enter your API key from https://spamtroll.io/dashboard"
echo "3. Enable spam filtering"
echo ""
echo "For support, visit: https://spamtroll.io/support"
echo ""

exit 0
