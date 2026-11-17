#!/usr/bin/env bash
# =============================================================================
# BADASS VM provisioning script (v5)
# Target : Ubuntu 24.04 LTS (noble) - works on BOTH arm64 (UTM/Mac) and amd64 (cluster)
# Usage  : bash setup_vm.sh        (normal user with sudo, NOT "sudo bash")
# Safe to re-run: every step checks if it is already done.
#
# Why not the GNS3 PPA?  ppa:gns3/ppa has no arm64 build of gns3-server/gns3-gui,
# so GNS3 is installed with pipx (pinned version) on both architectures instead.
# =============================================================================
set -euo pipefail

GNS3_VERSION="2.2.59"            # MUST be identical on the Mac VM and the cluster VM
UBRIDGE_REPO="https://github.com/GNS3/ubridge.git"
UBRIDGE_VERSION="v0.9.19"        # last 0.9.x release; matches GNS3 2.2
KB_LAYOUT="${KB_LAYOUT:-us}"     # override: KB_LAYOUT=fr bash setup_vm.sh

log()  { printf '\n\033[1;34m[*] %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[-] %s\033[0m\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
    echo "Do not run as root (use: bash setup_vm.sh). \$USER must be your login user." >&2
    exit 1
fi

ARCH="$(dpkg --print-architecture)"
log "Architecture: ${ARCH} / Ubuntu $(. /etc/os-release && echo "$VERSION_ID")"

# --- 1. APT packages ---------------------------------------------------------
log "Step 1/6: apt packages"
# Pre-answer the wireshark prompt: allow members of 'wireshark' group to capture
echo "wireshark-common wireshark-common/install-setuid boolean true" | sudo debconf-set-selections
# Pre-answer the display manager prompt (matters if gdm3 is already installed)
echo "lightdm shared/default-x-display-manager select lightdm" | sudo debconf-set-selections

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates curl git build-essential libpcap-dev \
    xfce4 xfce4-terminal lightdm \
    docker.io wireshark dynamips \
    pipx python3-dev \
    python3-pyqt6 python3-pyqt6.sip python3-pyqt6.qtsvg python3-pyqt6.qtwebsockets
sudo systemctl enable --now docker
ok "apt packages installed"

# --- 2. GNS3 server + GUI via pipx (pinned) ----------------------------------
log "Step 2/6: GNS3 ${GNS3_VERSION} via pipx"
pipx ensurepath >/dev/null
export PATH="$HOME/.local/bin:$PATH"
for pkg in gns3-server gns3-gui; do
    current="$(pipx runpip "$pkg" show "$pkg" 2>/dev/null | awk '/^Version:/{print $2}' || true)"
    if [ "$current" = "$GNS3_VERSION" ]; then
        ok "$pkg ${GNS3_VERSION} already installed"
    else
        # --system-site-packages: reuse PyQt6 from apt (PyPI wheels are unreliable on arm64)
        pipx install --force --system-site-packages "${pkg}==${GNS3_VERSION}"
        ok "$pkg ${GNS3_VERSION} installed"
    fi
done

# --- 3. ubridge from source (PPA has no arm64 build) -------------------------
log "Step 3/6: ubridge"
# Pin to the 0.9.x line: ubridge master (1.x, 2026) failed with gns3-server 2.2.59 in testing
if ubridge -v 2>/dev/null | grep -q "version ${UBRIDGE_VERSION#v}"; then
    ok "ubridge ${UBRIDGE_VERSION} already present: $(command -v ubridge)"
else
    tmp="$(mktemp -d)"
    git clone --depth 1 --branch "$UBRIDGE_VERSION" "$UBRIDGE_REPO" "$tmp/ubridge"
    make -C "$tmp/ubridge"
    sudo make -C "$tmp/ubridge" install   # also sets capabilities (setcap)
    rm -rf "$tmp"
    ok "ubridge built and installed"
fi

# --- 4. Group membership -----------------------------------------------------
log "Step 4/6: groups"
for g in docker wireshark; do
    if id -nG "$USER" | grep -qw "$g"; then
        ok "${USER} already in group $g"
    else
        sudo usermod -aG "$g" "$USER"
        ok "added ${USER} to group $g"
    fi
done

# --- 5. Desktop session + keyboard ------------------------------------------
log "Step 5/6: lightdm Xfce session + keyboard (${KB_LAYOUT})"
# Fix "Failed to start session": force the Xfce session for lightdm and for this user
sudo mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nuser-session=xfce\n' | sudo tee /etc/lightdm/lightdm.conf.d/50-xfce.conf >/dev/null
printf '[Desktop]\nSession=xfce\n' > "$HOME/.dmrc"
# Fix "Invalid password" at the graphical login: wrong XKB layout (e.g. fr instead of us)
if [ -f /etc/default/keyboard ]; then
    sudo sed -i "s/^XKBLAYOUT=.*/XKBLAYOUT=\"${KB_LAYOUT}\"/" /etc/default/keyboard
else
    printf 'XKBMODEL="pc105"\nXKBLAYOUT="%s"\nXKBVARIANT=""\nXKBOPTIONS=""\nBACKSPACE="guess"\n' "$KB_LAYOUT" \
        | sudo tee /etc/default/keyboard >/dev/null
fi
sudo setupcon --force >/dev/null 2>&1 || true   # may fail over ssh; applied at next boot anyway
ok "lightdm session=xfce, XKBLAYOUT=${KB_LAYOUT}"

# Fix black screen after login (VirtualBox on Apple Silicon only):
# arm64 VMs get the QemuRamFB controller = fixed-size framebuffer (simpledrm).
# VBoxClient resizes the screen to the window size (e.g. 1284x840_vbox) at login,
# which RamFB cannot display -> black screen. Hide VBoxClient autostart for this user.
if [ "$ARCH" = "arm64" ] && grep -qil "VBoxClient" /etc/xdg/autostart/*.desktop 2>/dev/null; then
    mkdir -p "$HOME/.config/autostart"
    for f in $(grep -il "VBoxClient" /etc/xdg/autostart/*.desktop); do
        dst="$HOME/.config/autostart/$(basename "$f")"
        cp "$f" "$dst"
        grep -q '^Hidden=true' "$dst" || echo "Hidden=true" >> "$dst"
    done
    ok "VBoxClient autostart hidden (arm64 RamFB black-screen fix)"
fi
# Second launch path: the X session script also starts the resizer (VBoxClient --vmsvga-session).
# Replace that one command with ':' (no-op keeps the shell block valid). Idempotent.
XCLIENT=/etc/X11/Xsession.d/98vboxadd-xclient
if [ "$ARCH" = "arm64" ] && [ -f "$XCLIENT" ] && grep -q '^[[:space:]]*/usr/bin/VBoxClient --vmsvga-session' "$XCLIENT"; then
    sudo sed -i 's|^\([[:space:]]*\)/usr/bin/VBoxClient --vmsvga-session|\1: # BADASS disabled (RamFB): /usr/bin/VBoxClient --vmsvga-session|' "$XCLIENT"
    ok "VBoxClient --vmsvga-session disabled in $XCLIENT"
fi

# --- 6. Verification ---------------------------------------------------------
log "Step 6/6: verification"
PYQT_CHECK="from PyQt6 import QtCore, QtGui, QtNetwork, QtWidgets, QtSvg, QtSvgWidgets, QtWebSockets, sip; print(QtCore.PYQT_VERSION_STR)"
GUI_PY="$HOME/.local/share/pipx/venvs/gns3-gui/bin/python"

echo "================ SUMMARY ================"
echo "arch          : ${ARCH}"
echo "gns3server    : $(gns3server --version 2>/dev/null || echo 'FAIL')"
echo "PyQt6 (venv)  : $("$GUI_PY" -c "$PYQT_CHECK" 2>/dev/null || echo 'FAIL')"
echo "ubridge       : $(ubridge -v 2>/dev/null | head -1 || echo FAIL) ($(command -v ubridge || echo none))"
echo "ubridge caps  : $(getcap "$(command -v ubridge)" 2>/dev/null | awk '{print $2}' || echo 'FAIL')"
echo "docker        : $(docker --version 2>/dev/null || echo 'FAIL')"
echo "dynamips      : $({ dynamips 2>&1 || true; } | grep -o "version [0-9.]*" | head -1)"   # dynamips without args exits non-zero
echo "dumpcap caps  : $(getcap /usr/bin/dumpcap 2>/dev/null | awk '{print $2}' || echo 'FAIL')"
echo "groups (file) : $(id -nG "$USER")"
echo "lightdm sess. : $(grep -h user-session /etc/lightdm/lightdm.conf.d/50-xfce.conf 2>/dev/null || echo FAIL)"
echo "keyboard      : $(grep -h ^XKBLAYOUT /etc/default/keyboard 2>/dev/null || echo FAIL)"
echo "========================================="
echo "[!] Reboot now (sudo reboot): applies groups, keyboard and the Xfce session. Then open a NEW ssh session."
