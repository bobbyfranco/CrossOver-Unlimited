#!/bin/sh

# Variables
FOLDER_NAME="CrossOverLicense"
PLIST_NAME="com.codeweavers.CrossOver.license.plist"
BOTTLES_PATH="$HOME/Library/Application Support/CrossOver/Bottles"
SCRIPT_URL="https://gist.githubusercontent.com/bobbyfranco/e0ac2e2e4f6e778d9605daf288ac999d/raw/2b3af115e0030004f7404370fca34f8615d26033/main.sh?token=$(date +%s)"

TOTAL_STEPS=3
STEP=0

function addStep() {
  ((STEP++))
  echo ""
  echo "\033[33m$STEP/$TOTAL_STEPS $1\033[0m"
}

function resetSystemReg() {
  local arquivo="$1"
  local data_actual=$(date +%Y-%m-%d)
  local backup_arquivo="${arquivo}.${data_actual}.bak"

  # Make a backup copy of the original file with the current date in the name
  cp "$arquivo" "$backup_arquivo"

  # proccess the file, removing the desired section
  awk '
  BEGIN { flag = 0; }
  /^\[Software\\\\CodeWeavers\\\\CrossOver\\\\cxoffice\]/ { flag = 1; }
  flag && /^$/ { flag = 0; next; }
  !flag
  ' "$arquivo" > "${arquivo}.tmp" && mv "${arquivo}.tmp" "$arquivo"
}

function resetBottle {
  local bottlePath="$1"
  local bottleName=$(basename "$bottlePath")

  rm -rf "$bottlePath"/.version
  rm -rf "$bottlePath"/.update-timestamp

  resetSystemReg "$bottlePath/system.reg"
  echo "\033[32m$bottleName reseted\033[0m"
}

function find_bottles() {
  find "$1" -name "system.reg" -exec dirname {} \;
}

execute_only() {
  addStep "Executing renew trial"
  local date=$(date +"%Y-%m-%d %H:%M:%S")
  defaults write com.codeweavers.CrossOver FirstRunDate -date "$date"
  defaults write com.codeweavers.CrossOver SULastCheckTime -date "$date"
  echo "\033[32mTrial start date updated to $date\033[0m"

  addStep "Finding bottles paths..."
  bottlePaths=$(find_bottles "$BOTTLES_PATH")

  if [[ -z "$bottlePaths" ]]; then
    echo "No bottles were found in the default path. Please enter the bottle path:"
    read userBottlePath
    # Try to find bottles in the path provided by the user
    bottlePaths=$(find_bottles "$userBottlePath")
  
    # If no path is found, the script ends with an error message
    if [[ -z "$bottlePaths" ]]; then
      echo "\033[31mNo bottles were found in the provided path. Exiting.\033[0m"
      exit 1
    fi
  fi

  # Fix IFS to handle spaces in the path
  OLD_IFS="$IFS"
  IFS=$'\n'
  for bottle in $bottlePaths; do
    echo "\033[32m$(basename "$bottle")\033[0m -> $bottle"
  done

  addStep "Resetting bottles install times"
  for bottle in $bottlePaths; do
    resetBottle "$bottle"
  done

  IFS="$OLD_IFS"
}

# Function for install
install() {
  TOTAL_STEPS=$((TOTAL_STEPS + 2))
  addStep "Trying to execute the script..."
  execute_only

  addStep "Installing Service..."

  mkdir -p "$HOME/$FOLDER_NAME"
  curl -o "$HOME/$FOLDER_NAME"/main.sh "$SCRIPT_URL" > /dev/null 2>&1
  chmod +x "$HOME/$FOLDER_NAME"/main.sh

  local plistPath="$HOME/Library/LaunchAgents/$PLIST_NAME"
  # if script alredy exists, unload and remove it
  if [ -f "$plistPath" ]; then
    launchctl unload "$plistPath" > /dev/null 2>&1
    rm "$plistPath"
  fi

  # Create the macOS service file
  cat > "$plistPath" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/$FOLDER_NAME/main.sh</string>
        <string>execute</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>864000</integer>
</dict>
</plist>
EOF
    echo "\033[32mService Installation completed.\033[0m"
    echo "Starting the service..."
    launchctl load "$plistPath"

}

# Function for uninstall
uninstall() {
  TOTAL_STEPS=2
  addStep "Uninstalling the service..."

  local plistPath="$HOME/Library/LaunchAgents/$PLIST_NAME"
  # If the plist exists, unload and remove it
  if [ -f "$plistPath" ]; then
    launchctl unload "$plistPath" > /dev/null 2>&1
    rm "$plistPath"
  else
    echo "\033[33mService plist not found. Skipping unload.\033[0m"
  fi

  addStep "Removing script directory..."
  # Remove the script directory
  if [ -d "$HOME/$FOLDER_NAME" ]; then
    echo "Removing script directory..."
    rm -rf "$HOME/$FOLDER_NAME"
    echo "\033[32mScript directory removed.\033[0m"
  else
    echo "\033[33mScript directory not found. Skipping removal.\033[0m"
  fi

  echo "\033[32mUninstallation completed.\033[0m"
}

# Check arguments
if [ "$#" -eq 1 ]; then
  if [ "$1" == "execute" ]; then
    execute_only
  elif [ "$1" == "install" ]; then
    install
  elif [ "$1" == "uninstall" ]; then
    uninstall
  else
    echo "Invalid argument. Use 'execute' or 'install'."
  fi
else
  echo "Do you wish to 'execute' the script or 'install'? [\033[37mexecute\033[0m/\033[33minstall\033[0m]"
  echo "\033[37minstall is the default choice.. you can just press enter\033[0m"
  read response

  if [ "$response" == "execute" ]; then
    execute_only
  elif [ "$response" == "install" ]; then
    install
  else
    echo "No valid option. Installing by default..."
    install
  fi
fi
