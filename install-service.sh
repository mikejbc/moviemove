#!/bin/bash

# Movie Organizer Service Installation Script
# This script installs the movie organizer as a systemd service

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="movie-organizer"
SERVICE_USER="movieorg"
SERVICE_GROUP="movieorg"
SCRIPT_NAME="movie_organizer.sh"
SERVICE_FILE="movie-organizer.service"

# Paths
INSTALL_DIR="/usr/local/bin"
SERVICE_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/movie-organizer"
CACHE_DIR="/var/cache/movie-organizer" 
LOG_DIR="/var/log"
HOME_DIR="/var/lib/movie-organizer"
DOC_DIR="/usr/local/share/movie-organizer"

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_files() {
    if [[ ! -f "$SCRIPT_NAME" ]]; then
        print_error "Script file '$SCRIPT_NAME' not found in current directory"
        exit 1
    fi
    
    if [[ ! -f "$SERVICE_FILE" ]]; then
        print_error "Service file '$SERVICE_FILE' not found in current directory"
        exit 1
    fi
}

create_user() {
    if ! id "$SERVICE_USER" &>/dev/null; then
        print_status "Creating user $SERVICE_USER..."
        useradd --system --shell /bin/false --home-dir "$HOME_DIR" --create-home "$SERVICE_USER"
    else
        print_status "User $SERVICE_USER already exists"
    fi
}

create_directories() {
    print_status "Creating directories..."
    
    # Create directories
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CACHE_DIR"
    mkdir -p "$HOME_DIR"
    mkdir -p "$DOC_DIR"
    
    # Set ownership
    chown "$SERVICE_USER":"$SERVICE_GROUP" "$CACHE_DIR"
    chown "$SERVICE_USER":"$SERVICE_GROUP" "$HOME_DIR"
    chown root:root "$CONFIG_DIR"
    
    # Set permissions
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$CACHE_DIR"
    chmod 755 "$HOME_DIR"
    chmod 755 "$DOC_DIR"
}

install_script() {
    print_status "Installing script to $INSTALL_DIR..."
    cp "$SCRIPT_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    chown root:root "$INSTALL_DIR/$SCRIPT_NAME"
}

install_service() {
    print_status "Installing systemd service..."
    cp "$SERVICE_FILE" "$SERVICE_DIR/"
    chmod 644 "$SERVICE_DIR/$SERVICE_FILE"
    chown root:root "$SERVICE_DIR/$SERVICE_FILE"
}

install_documentation() {
    print_status "Installing documentation..."
    if [[ -f "README.md" ]]; then
        cp "README.md" "$DOC_DIR/"
        chmod 644 "$DOC_DIR/README.md"
        chown root:root "$DOC_DIR/README.md"
    fi
}

create_mnamer_config() {
    print_status "Creating default mnamer configuration..."
    
    if [[ ! -f "$CONFIG_DIR/mnamer.json" ]]; then
        cat > "$CONFIG_DIR/mnamer.json" << 'EOF'
{
  "api_key_tmdb": "",
  "batch": true,
  "config_ignore": false,
  "episode_api": "tvdb",
  "episode_directory": "/mnt/smb-share/tv",
  "episode_format": "{series} - S{season:02d}E{episode:02d} - {title}",
  "hits": 5,
  "ignore": [".*sample.*", ".*trailer.*", ".*preview.*"],
  "language": "en",
  "lower": false,
  "mask": ["nfo", "txt", "srt"],
  "movie_api": "tmdb",
  "movie_directory": "/mnt/smb-share/movies",
  "movie_format": "{title} ({year})",
  "no_cache": false,
  "no_guess": false,
  "no_overwrite": false,
  "no_style": false,
  "recurse": true,
  "scene": false,
  "verbose": 1
}
EOF
        chmod 644 "$CONFIG_DIR/mnamer.json"
        chown root:root "$CONFIG_DIR/mnamer.json"
        
        print_warning "Please edit $CONFIG_DIR/mnamer.json to configure your API keys and paths"
    else
        print_status "mnamer config already exists"
    fi
}

create_logrotate_config() {
    print_status "Creating logrotate configuration..."
    
    cat > "/etc/logrotate.d/movie-organizer" << EOF
/var/log/movie_organizer.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su $SERVICE_USER $SERVICE_GROUP
}
EOF
    chmod 644 "/etc/logrotate.d/movie-organizer"
}

reload_systemd() {
    print_status "Reloading systemd daemon..."
    systemctl daemon-reload
}

show_next_steps() {
    print_status "Installation completed successfully!"
    echo
    echo "Next steps:"
    echo "1. Edit the configuration:"
    echo "   sudo nano $CONFIG_DIR/mnamer.json"
    echo "   sudo nano $INSTALL_DIR/$SCRIPT_NAME  # Update SMB paths"
    echo
    echo "2. Install mnamer if not already installed:"
    echo "   pip install mnamer"
    echo
    echo "3. Test the service:"
    echo "   sudo systemctl start $SERVICE_NAME"
    echo "   sudo systemctl status $SERVICE_NAME"
    echo
    echo "4. Enable auto-start:"
    echo "   sudo systemctl enable $SERVICE_NAME"
    echo
    echo "5. View logs:"
    echo "   sudo journalctl -u $SERVICE_NAME -f"
    echo "   sudo tail -f /var/log/movie_organizer.log"
    echo
    echo "Configuration files:"
    echo "  Script: $INSTALL_DIR/$SCRIPT_NAME"
    echo "  Service: $SERVICE_DIR/$SERVICE_FILE"
    echo "  Config: $CONFIG_DIR/mnamer.json"
    echo "  Logs: /var/log/movie_organizer.log"
}

# Main installation process
main() {
    print_status "Starting Movie Organizer service installation..."
    
    check_root
    check_files
    create_user
    create_directories
    install_script
    install_service
    install_documentation
    create_mnamer_config
    create_logrotate_config
    reload_systemd
    
    show_next_steps
}

# Run main function
main "$@"
