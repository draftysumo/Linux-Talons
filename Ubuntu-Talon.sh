#!/bin/bash
set -uuo pipefail

# ===============================
# Setup Logging
# ===============================
exec > >(tee -i setup.log)
exec 2>&1

# ===============================
# Root Check
# ===============================
if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root. Try: sudo $0"
  exit 1
fi

USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)

# ===============================
# Helper Functions
# ===============================
try_or_continue() {
    local cmd="$1"
    local alt="$2"

    echo "⚡ Running: $cmd"
    if ! eval "$cmd"; then
        if [[ -n "$alt" ]]; then
            echo "⚠️ Failed, attempting alternative: $alt"
            eval "$alt" || echo "❌ Alternative also failed, continuing..."
        else
            echo "❌ Command failed, continuing..."
        fi
    fi
}

remove_firefox() {
    echo "🗑️ Removing Firefox..."
    try_or_continue "snap list | grep -q firefox && snap remove --purge firefox" ""
    try_or_continue "apt list --installed 2>/dev/null | grep -q firefox && apt remove --purge -y firefox" ""
    rm -rf /etc/firefox /usr/lib/firefox /usr/lib/firefox-addons /usr/share/firefox /usr/share/firefox-addons || true
}

install_flatpak_app() {
    local app_id="$1"
    try_or_continue "sudo -u \"$SUDO_USER\" flatpak install -y --noninteractive flathub \"$app_id\"" ""
}

# ===============================
# System Update & Base Libraries
# ===============================
echo "🔄 Updating system & installing base packages..."
try_or_continue "apt update && apt upgrade -y" ""
try_or_continue "apt install -y curl jq flatpak gnome-software gnome-software-plugin-flatpak preload gnome-shell gnome-shell-extensions software-properties-common libvlc-dev ffmpeg stacer" ""

# GNOME Shell Extension Manager
echo "🔧 Installing GNOME Shell Extension Manager..."
try_or_continue "apt install -y gnome-shell-extension-manager" ""

# Flatpak & Flathub
echo "🌐 Setting up Flatpak and Flathub..."
try_or_continue "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo" ""

# ===============================
# Firefox Replacement
# ===============================
read -rp "🌐 Do you want to replace Firefox? (y/n): " replace_ff
if [[ "$replace_ff" =~ ^[Yy]$ ]]; then
  echo "Choose a replacement browser:"
  select browser_choice in "Brave" "LibreWolf"; do
    case $browser_choice in
      Brave)
        remove_firefox
        echo "🦁 Installing Brave Browser..."
        try_or_continue "curl -fsS https://dl.brave.com/install.sh | sh" ""
        break
        ;;
      LibreWolf)
        remove_firefox
        echo "🦊 Installing LibreWolf via Flatpak..."
        install_flatpak_app "io.gitlab.librewolf-community"
        break
        ;;
      *)
        echo "❌ Invalid option. Choose 1 or 2."
        ;;
    esac
  done
else
  echo "✅ Keeping Firefox."
fi

# ===============================
# Remove Snap Store
# ===============================
echo "🧹 Removing Snap Store (if present)..."
try_or_continue "snap list | grep -q snap-store && snap remove --purge snap-store" "echo 'No Snap Store found, skipping.'"

# ===============================
# Timeshift Installation
# ===============================
echo "⏳ Installing Timeshift..."
try_or_continue "add-apt-repository -y ppa:teejee2008/timeshift" ""
try_or_continue "apt update" ""
try_or_continue "apt install -y timeshift" ""

# ===============================
# FSearch Installation
# ===============================
echo "🔍 Installing FSearch..."
try_or_continue "add-apt-repository -y ppa:christian-boxdoerfer/fsearch-stable" ""
try_or_continue "apt update" ""
try_or_continue "apt install -y fsearch" ""

# ===============================
# Clapper via Flatpak
# ===============================
echo "🎬 Installing Clapper via Flatpak..."
install_flatpak_app "com.github.rafostar.Clapper"

# ===============================
# Developer Tools
# ===============================
echo "💻 Developer Tools Installation"
read -rp "Install Node.js & npm? (y/n): " install_node
if [[ "$install_node" =~ ^[Yy]$ ]]; then
  try_or_continue "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -" ""
  try_or_continue "apt install -y nodejs" ""
fi

read -rp "Install Python? (y/n): " install_python
if [[ "$install_python" =~ ^[Yy]$ ]]; then
  try_or_continue "apt install -y python3 python3-pip python3-venv" ""
fi

read -rp "Install Visual Studio Code? (y/n): " install_vscode
if [[ "$install_vscode" =~ ^[Yy]$ ]]; then
  try_or_continue "curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg" ""
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
  try_or_continue "apt update" ""
  try_or_continue "apt install -y code" ""
fi

# ===============================
# Office Suite
# ===============================
echo "📂 Choose an Office suite to install:"
select office_choice in "LibreOffice" "OnlyOffice"; do
  case $office_choice in
    LibreOffice)
      echo "📦 Installing LibreOffice..."
      try_or_continue "install_flatpak_app 'org.libreoffice.LibreOffice'" "apt install -y libreoffice"
      break
      ;;
    OnlyOffice)
      echo "📦 Installing OnlyOffice..."
      TMP_DIR=$(mktemp -d)
      cd "$TMP_DIR" || continue
      try_or_continue "wget https://download.onlyoffice.com/install/desktop/editors/linux/onlyoffice-desktopeditors_amd64.deb" ""
      try_or_continue "apt install -y ./onlyoffice-desktopeditors_amd64.deb" ""
      cd - && rm -rf "$TMP_DIR"
      break
      ;;
    *)
      echo "❌ Invalid option. Choose 1 or 2."
      ;;
  esac
done

# ===============================
# Disk Utilities
# ===============================
echo "💽 Replacing gdisk with gpart..."
try_or_continue "apt remove -y gdisk" ""
try_or_continue "apt install -y gpart" ""

# ===============================
# Final Cleanup
# ===============================
echo "🧽 Final system cleanup..."
try_or_continue "apt autoremove -y" ""
try_or_continue "apt clean" ""
try_or_continue "apt autoclean -y" ""

echo "✅ Setup complete! Full log saved in setup.log"
