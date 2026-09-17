#!/bin/bash

# Colors
W=$'\033[0m'
R=$'\033[31m'
G=$'\033[32m'
O=$'\033[33m'
GR=$'\033[37m'

# Configuration
PLIST_NAME="com.codeweavers.CrossOver.license.plist"

SCRIPT_URL="https://gist.githubusercontent.com/bobbyfranco/e0ac2e2e4f6e778d9605daf288ac999d/raw/f7c20d4a2af6264ca8f72baa7a84c34dd9336fec/crossover?token$(date +%s)"

INSTALL_DIR="$HOME/.local/bin"
INSTALL_PATH="$INSTALL_DIR/crossover"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"

TOTAL_STEPS=5
STEP=0

# Do NOT run a user-level installer as root.
if [[ $EUID -eq 0 ]]; then
    printf "%sError: do not run this installer with sudo.%s\n" "$R" "$W"
    printf "%sRun it as: ./crossover.sh%s\n" "$O" "$W"
    exit 1
fi

addStep() {
    ((STEP++))
    printf "\n%s%s/%s %s%s\n" \
        "$O" "$STEP" "$TOTAL_STEPS" "$1" "$W"
}

install() {
    addStep "Installing command..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$HOME/Library/LaunchAgents"

    if ! curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH"; then
        printf "%sFailed to download command.%s\n" "$R" "$W"
        return 1
    fi

    chmod 755 "$INSTALL_PATH"

    printf "%sCommand installed:%s %s\n" \
        "$G" "$W" "$INSTALL_PATH"

    addStep "Installing service..."

    # Remove an existing user LaunchAgent first.
    launchctl bootout \
        "gui/$(id -u)" \
        "$PLIST_PATH" \
        >/dev/null 2>&1 || true

    rm -f "$PLIST_PATH"

    cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>

    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_PATH</string>
        <string>renew</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>StartInterval</key>
    <integer>864000</integer>
</dict>
</plist>
EOF

    if ! plutil -lint "$PLIST_PATH" >/dev/null; then
        printf "%sLaunchAgent plist is invalid.%s\n" "$R" "$W"
        return 1
    fi

    if ! launchctl bootstrap \
        "gui/$(id -u)" \
        "$PLIST_PATH"; then

        printf "%sFailed to start LaunchAgent.%s\n" "$R" "$W"
        return 1
    fi

    printf "%sService installation completed.%s\n" "$G" "$W"
}

uninstall() {
    TOTAL_STEPS=2
    STEP=0

    addStep "Uninstalling service..."

    launchctl bootout \
        "gui/$(id -u)" \
        "$PLIST_PATH" \
        >/dev/null 2>&1 || true

    if [[ -f "$PLIST_PATH" ]]; then
        rm -f "$PLIST_PATH"
        printf "%sLaunchAgent removed.%s\n" "$G" "$W"
    else
        printf "%sLaunchAgent not found. Skipping.%s\n" "$O" "$W"
    fi

    addStep "Removing command..."

    if [[ -f "$INSTALL_PATH" ]]; then
        rm -f "$INSTALL_PATH"
        printf "%sCommand removed.%s\n" "$G" "$W"
    else
        printf "%sCommand not found. Skipping.%s\n" "$O" "$W"
    fi

    printf "\n%sUninstallation completed.%s\n" "$G" "$W"
}

renew() {
  addStep "Executing renew trial"
  local date=$(date +"%Y-%m-%d %H:%M:%S")
  defaults write com.codeweavers.CrossOver FirstRunDate -date "$date"
  defaults write com.codeweavers.CrossOver SULastCheckTime -date "$date"
  printf "\n${G}Trial start date updated to $date ${W}"

  addStep "Finding bottles paths..."
  bottlePaths=$(find_bottles "$BOTTLES_PATH")

  if [[ -z "$bottlePaths" ]]; then
    printf "\nNo bottles were found in the default path. Please enter the bottle path:"
    read userBottlePath
    # Try to find bottles in the path provided by the user
    bottlePaths=$(find_bottles "$userBottlePath")
  
    # If no path is found, the script ends with an error message
    if [[ -z "$bottlePaths" ]]; then
      printf "\n${O} No bottles were found in the provided path. Exiting.${W}"
      exit 1
    fi
  fi

  # Fix IFS to handle spaces in the path
  OLD_IFS="$IFS"
  IFS=$'\n'
  for bottle in $bottlePaths; do
    printf "\n${G} $(basename "$bottle")${O} -> $bottle ${W}"
  done

  addStep "Resetting bottles install times"
  for bottle in $bottlePaths; do
    resetBottle "$bottle"
  done

  IFS="$OLD_IFS"
}

# Check arguments
if [ "$#" -eq 1 ]; then
  if [ "$1" == "renew" ]; then
    renew
  elif [ "$1" == "install" ]; then
    install
  elif [ "$1" == "uninstall" ]; then
    uninstall
  else
    printf "Invalid argument. Use 'renew' or 'install'."
  fi
else
  printf "\nDo you wish to 'renew' the script or 'install'? ${GR}renew${W}/${O}install${W}"
  printf "\n${GR}install is the default choice.. you can just press enter${W}"
  read response

  if [ "$response" == "renew" ]; then
    renew
  elif [ "$response" == "install" ]; then
    install
  else
    printf "No valid option. Installing by default..."
    install
  fi
fi
