#!/bin/env bash

set -euo pipefail

# Configuration
GITHUB_DOTFILES_REPO="https://github.com/codenobacon4u/dotfiles.git"
DOTFILES_DIR="$HOME/.dotfiles"
CONFIG_DIR="./config/arch"

# Default values
TARGET_DISTRO=""
TYPE=minimal
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [ "$VERBOSE" = true ]; then
        echo -e "[DEBUG] $1"
    fi
}

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -d, --distro DISTRO   Specify distribution to install [ubuntu|debian|fedora|arch] (detects based on host instance if not set)
    -t, --type TYPE       Specify the install type [desktop|desktop-hypr|laptop-hypr|server|minimal]
    -g, --git REPO        Specify a dotfile/config git repo (assumes there's an install.sh to run)
    -c, --config DIR      Specify a config files or directory if used to override the target distro installer's config
    -n, --hostname NAME   Specify a hostname for the system
    -u, --user USER       Specify a user account for the system
    -v, --verbose         Enable verbose output
    -h, --help            Show this help message

Example:
    $(basename "$0") --distro ubuntu --verbose
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--distro)
                if [[ -n "$2" && "$2" =~ ^(ubuntu|debian|fedora|rocky|arch)$ ]]; then
                    TARGET_DISTRO="$2"
                    shift 2
                else
                    log_error "Invalid distribution specified"
                    print_usage
                    exit 1
                fi
                ;;
            -t|--type)
                if [[ -n "$2" && "$2" =~ ^(desktop|desktop-hypr|laptop-hypr|server|minimal)$ ]]; then
                    TYPE="$2"
                    shift 2
                else
                    log_error "Invalid install type specified"
                    print_usage
                    exit 1
                fi
                ;;
            -g|--git)
                if [[ -n "$2" ]]; then
                    GITHUB_DOTFILES_REPO="$2"
                    shift 2
                else
                    log_error "No git repo specified"
                    print_usage
                    exit 1
                fi
                ;;
            -c|--config)
                if [[ -n "$2" ]]; then
                    CONFIG_DIR="$2"
                    shift 2
                else
                    log_error "No config directory specified"
                    print_usage
                    exit 1
                fi
                ;;
            -n|--hostname)
                if [[ -n "$2" ]]; then
                    HOST_NAME="$2"
                    shift 2
                else
                    log_error "No hostname specified"
                    print_usage
                    exit 1
                fi
                ;;
            -u|--user)
                if [[ -n "$2" ]]; then
                    USER_NAME="$2"
                    shift 2
                else
                    log_error "No username specified"
                    print_usage
                    exit 1
                fi
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

init_vars() {
    if [ -n "$TARGET_DISTRO" ]; then
        DISTRO="$TARGET_DISTRO"
        VERSION=""
        log_info "Specified distro: $DISTRO"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    else
        log_error "Cannot detect Linux distro and no target distro was specified."
        exit 1
    fi
}

modify_line_in_file() {
    local file="$1"
    local search_pattern="$2"
    local replacement="$3"
    
    if [ ! -f "$file" ]; then
        log_error "File not found: $file"
        return 1
    fi
    
    log_debug "Modifying file: $file"
    log_debug "Search pattern: $search_pattern"
    log_debug "Replacement: $replacement"
    
    # Create backup of original file
    cp "$file" "${file}.bak"
    
    # Perform the replacement
    if sed -i "s/${search_pattern}/${replacement}/" "$file"; then
        # Show the change in verbose mode
        if [ "$VERBOSE" = true ]; then
            log_debug "Changed line now reads as:"
            grep "$replacement" "$file" || true
        fi
    else
        log_error "Failed to modify file"
        # Restore backup
        mv "${file}.bak" "$file"
        return 1
    fi
}

run_install() {
    case $DISTRO in
    "arch")
        local config_file="./alis-${TYPE}.conf"
        log_debug "Installing ArchLinux using picodotdev/alis..."
        loadkeys us
        curl -sL https://raw.githubusercontent.com/picodotdev/alis/main/download.sh | bash
        cp -R "${CONFIG_DIR}/*" .

        modify_line_in_file "${config_file}" 'LOG_TRACE=".*"' "LOG_TRACE=\"${VERBOSE}\""
        if [ -n "$HOST_NAME" ]; then
            modify_line_in_file "${config_file}" 'HOSTNAME=".*"' "HOSTNAME=\"${HOST_NAME}\""
        fi
        if [ -n "$USER_NAME" ]; then
            modify_line_in_file "${config_file}" 'USER_NAME=".*"' "USER_NAME=\"${USER_NAME}\""
        fi
        mv "${config_file}" "./alis.conf"
        mv "./alis-packages-${TYPE}.conf" "./alis-packages.conf"
        ./alis.sh
    *)
        log_error "Unsupported distro: $DISTRO"
        exit 1
        ;;
    esac
}

setup_dotfiles() {
    log_info "Setting up dotfiles..."
    if [ -d "$DOTFILES_DIR" ]; then
        log_warn "Dotfiles directory already exists. Backing up..."
        mv "$DOTFILES_DIR" "${DOTFILES_DIR}.bak"
    fi

    log_debug "Cloning dotfiles from: $GITHUB_DOTFILES_REPO"
    git clone "$GITHUB_DOTFILES_REPO" "$DOTFILES_DIR"
    
    if [ -f "$DOTFILES_DIR/install.sh" ]; then
        log_info "Running dotfiles install script..."
        bash "$DOTFILES_DIR/install.sh"
    else
        log_warn "No install.sh found in dotfiles repository"
    fi
}

main() {
    parse_args "$@"

    init_vars
    log_info "Installing distro: $DISTRO $VERSION"

    run_install

    setup_dotfiles

    log_info "System has been initialized successfully!"
}

main "$@"