#!/usr/bin/env bash
###############################################################################
# backup-setup.sh — Backup solution for Radxa NIO 12L (8GB RAM)
#
# Adds a second "use" for the 8GB board: automated backup of documents,
# configs, and AI model cache to a remote or local destination.
#
# Tools used: rclone (github:rclone/rclone) + restic (github:restic/restic)
# All from existing open-source tools — no custom backup code written.
#
# Usage:
#   sudo ./setup/backup-setup.sh --install
#   sudo ./setup/backup-setup.sh --backup
#   sudo ./setup/backup-setup.sh --restore TARGET
#   sudo ./setup/backup-setup.sh --status
###############################################################################
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; }

# ── Defaults ────────────────────────────────────────────────────────────────
REMOTE_TYPE="local"          # local | sftp | s3 | crypt
REMOTE_HOST=""
REMOTE_PATH="/mnt/backup"
RESTIC_PASSWORD_FILE="/etc/nio12l-backup/restic-password"

# ── Step 1: Install rclone ──────────────────────────────────────────────────
install_rclone() {
    info "Step 1: Installing rclone..."
    if command -v rclone >/dev/null 2>&1; then
        ok "rclone already installed: $(rclone version | head -1)"
        return
    fi
    # Install from official rclone.sh (no custom code)
    curl -fsSL https://rclone.org/install.sh | bash 2>/dev/null \
        || warn "rclone.sh install failed — using apt"
    apt-get install -y rclone 2>/dev/null || true
    if command -v rclone >/dev/null 2>&1; then
        ok "rclone installed: $(rclone version | head -1)"
    else
        err "Failed to install rclone"
    fi
}

# ── Step 2: Install restic ──────────────────────────────────────────────────
install_restic() {
    info "Step 2: Installing restic..."
    if command -v restic >/dev/null 2>&1; then
        ok "restic already installed: $(restic version)"
        return
    fi
    # Install from official restic releases (no custom code)
    local arch=$(uname -m)
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local url="https://github.com/restic/restic/releases/latest/download/restic_${os}_${arch}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o /usr/local/bin/restic "$url" \
            && chmod +x /usr/local/bin/restic \
            && ok "restic installed: $(restic version)"
        return
    fi
    apt-get install -y restic 2>/dev/null || true
    if command -v restic >/dev/null 2>&1; then
        ok "restic installed via apt: $(restic version)"
    else
        err "Failed to install restic"
    fi
}

# ── Step 3: Configure backup destination ────────────────────────────────────
configure_backup() {
    info "Step 3: Configuring backup destination..."

    local config_dir="/etc/nio12l-backup"
    mkdir -p "$config_dir"
    chmod 700 "$config_dir"

    # Generate a random restic password
    if [[ ! -f "$RESTIC_PASSWORD_FILE" ]]; then
        info "Generating restic password..."
        openssl rand -base64 32 > "$RESTIC_PASSWORD_FILE"
        chmod 600 "$RESTIC_PASSWORD_FILE"
        ok "Restic password generated"
    fi

    # Create rclone configuration
    local rclone_conf="/etc/nio12l-backup/rclone.conf"
    cat > "$rclone_conf" <<EOF
[backup]
type = $REMOTE_TYPE
EOF

    case "$REMOTE_TYPE" in
        local)
            echo "remote = $REMOTE_PATH" >> "$rclone_conf"
            ;;
        sftp)
            echo "host = $REMOTE_HOST" >> "$rclone_conf"
            echo "path = $REMOTE_PATH" >> "$rclone_conf"
            ;;
        s3)
            echo "provider = Other" >> "$rclone_conf"
            echo "endpoint = $REMOTE_HOST" >> "$rclone_conf"
            echo "path = $REMOTE_PATH" >> "$rclone_conf"
            ;;
        crypt)
            echo "remote = $REMOTE_PATH" >> "$rclone_conf"
            ;;
    esac

    ok "rclone config written to $rclone_conf"
}

# ── Step 4: Initialize restic repository ────────────────────────────────────
init_repo() {
    info "Step 4: Initializing restic repository..."
    if restic snapshots 2>/dev/null | grep -q .; then
        ok "Repository already initialized"
        return
    fi

    # Create backup directory
    local backup_dir="/var/lib/nio12l-backup"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"

    # Initialize repository based on remote type
    case "$REMOTE_TYPE" in
        local)
            restic -r "local:/var/lib/nio12l-backup" init 2>/dev/null \
                || warn "Repository already initialized or error"
            ;;
        sftp|s3|crypt)
            # For remote, use rclone as the remote
            local rclone_remote="rclone:backup"
            restic -r "$rclone_remote" init 2>/dev/null \
                || warn "Repository init skipped (use --backup to create)"
            ;;
    esac

    if restic snapshots 2>/dev/null | grep -q .; then
        ok "Repository initialized"
    else
        warn "Repository not initialized — run --backup to create"
    fi
}

# ── Step 5: Perform backup ──────────────────────────────────────────────────
do_backup() {
    info "Step 5: Performing backup..."

    local backup_dir="/var/lib/nio12l-backup"
    local rclone_conf="/etc/nio12l-backup/rclone.conf"
    export RCLONE_CONFIG="$rclone_conf"
    export RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE"

    # Create repository if needed
    if ! restic snapshots 2>/dev/null | grep -q .; then
        info "Creating repository first time..."
        case "$REMOTE_TYPE" in
            local)
                restic -r "local:/var/lib/nio12l-backup" init 2>/dev/null \
                    || warn "Could not init local repo"
                ;;
            *)
                local rclone_remote="rclone:backup"
                restic -r "$rclone_remote" init 2>/dev/null \
                    || warn "Could not init remote repo"
                ;;
        esac
    fi

    if ! restic snapshots 2>/dev/null | grep -q .; then
        err "No restic repository available"
        return 1
    fi

    # Backup source directories
    local now=$(date +%Y%m%d_%H%M%S)
    local tag="auto-$now"

    info "Backing up: /etc, /home, /var/lib/nio12l-dashboard, /usr/local/share/npu-models..."
    restic -r "local:$backup_dir" backup \
        --tag "$tag" \
        /etc \
        /home \
        /var/lib/nio12l-dashboard \
        /var/log \
        /usr/local/share/npu-models 2>&1 | tail -5

    local latest=$(restic snapshots -r "local:$backup_dir" latest | tail -1)
    ok "Backup complete: $latest"
}

# ── Step 6: Verify backup ───────────────────────────────────────────────────
verify_backup() {
    info "Step 6: Verifying backup..."
    local count=$(restic snapshots 2>/dev/null | grep -c "^snap")
    if [[ "$count" -gt 0 ]]; then
        ok "Repository has $count snapshots"
        restic snapshots 2>/dev/null | tail -3 | while read -r line; do
            echo "  $line"
        done
    else
        warn "No snapshots found"
    fi
}

# ── Step 7: Restore ─────────────────────────────────────────────────────────
do_restore() {
    local target="${1:-latest}"
    info "Step 7: Restoring from target '$target'..."

    export RESTIC_PASSWORD_FILE="$RESTIC_PASSWORD_FILE"

    case "$target" in
        latest)
            restic -r "local:/var/lib/nio12l-backup" restore latest --target /tmp/nio12l-restore 2>&1 | tail -5
            ;;
        *)
            restic -r "local:/var/lib/nio12l-backup" restore "$target" --target /tmp/nio12l-restore 2>&1 | tail -5
            ;;
    esac

    if [[ -d "/tmp/nio12l-restore" ]]; then
        ok "Restore complete to /tmp/nio12l-restore"
        echo "  Contents:"
        ls -la /tmp/nio12l-restore | head -10
    else
        err "Restore failed"
        return 1
    fi
}

# ── Step 8: Status ──────────────────────────────────────────────────────────
show_status() {
    info "Status:"
    if command -v restic >/dev/null 2>&1; then
        ok "restic: $(restic version)"
    else
        warn "restic: not installed"
    fi
    if command -v rclone >/dev/null 2>&1; then
        ok "rclone: $(rclone version | head -1)"
    else
        warn "rclone: not installed"
    fi

    if [[ -f "$RESTIC_PASSWORD_FILE" ]]; then
        ok "Restic password: configured"
    else
        warn "Restic password: not configured"
    fi

    local snapshots=$(restic snapshots 2>/dev/null | grep -c "^snap")
    if [[ "$snapshots" -gt 0 ]]; then
        ok "Snapshots: $snapshots"
    else
        warn "Snapshots: 0"
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    local action="${1:-status}"

    info "NIO 12L Backup Setup"
    echo "=============================================="

    case "$action" in
        --install)
            install_rclone
            echo ""
            install_restic
            echo ""
            configure_backup
            echo ""
            init_repo
            ;;
        --backup)
            do_backup
            ;;
        --restore)
            do_restore "${2:-latest}"
            ;;
        --status)
            show_status
            ;;
        *)
            echo "Usage: $0 {--install|--backup|--restore [target]|--status}"
            echo "  --install    Install rclone + restic and configure backup"
            echo "  --backup     Perform a backup"
            echo "  --restore    Restore from a target (default: latest)"
            echo "  --status     Show backup status"
            exit 1
            ;;
    esac

    echo "=============================================="
    ok "Done!"
}

main "$@"
