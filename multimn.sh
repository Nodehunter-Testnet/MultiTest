#!/bin/bash

# Author: ElysiumRoyaleOfficial
# Modified by: User for Shared Blockchain Directory
# Source: https://github.com/ElysiumRoyale/ROYAL-MultiMN

# Colors for console output
readonly GRAY='\e[1;30m'
readonly DARKRED='\e[0;31m'
readonly RED='\e[1;31m'
readonly DARKGREEN='\e[0;32m'
readonly GREEN='\e[1;32m'
readonly DARKYELLOW='\e[0;33m'
readonly YELLOW='\e[1;33m'
readonly DARKBLUE='\e[0;34m'
readonly BLUE='\e[1;34m'
readonly DARKMAGENTA='\e[0;35m'
readonly MAGENTA='\e[1;35m'
readonly DARKCYAN='\e[0;36m'
readonly CYAN='\e[1;36m'
readonly UNDERLINE='\e[1;4m'
readonly NC='\e[0m'

PROFILE_NAME=""
COIN_NAME=""
COIN_DAEMON=""
COIN_CLI=""
COIN_FOLDER=""
COIN_CONFIG=""
RPC_PORT=""
COIN_SERVICE=""
MULTI_COUNT=""
EXEC_COIN_CLI=""
EXEC_COIN_DAEMON=""
IP=""
IP_TYPE=""
NEW_RPC=""
NEW_KEY=""
INSTALL_BOOTSTRAP=""
FORCE_LISTEN=""
SHARED_DIR="/root/shared_elysium_chain"

function load_profile() {
  # Load the masternode profile and initialize variables
  # <$1 = profile_name> | [$2 = check_exec]

  if [[ ! -f ".multimn/$1" ]]; then
    echo -e "${BLUE}$1${NC} profile hasn't been added"
    exit
  fi

  local -A prof=$(get_conf .multimn/$1)
  PROFILE_NAME="$1"
  COIN_NAME="${prof[COIN_NAME]}"
  COIN_DAEMON="${prof[COIN_DAEMON]}"
  COIN_CLI="${prof[COIN_CLI]}"
  COIN_FOLDER="${prof[COIN_FOLDER]}"
  COIN_CONFIG="${prof[COIN_CONFIG]}"
  RPC_PORT="${prof[RPC_PORT]}"
  EXEC_COIN_DAEMON="${prof[COIN_PATH]}$COIN_DAEMON"
  EXEC_COIN_CLI="${prof[COIN_PATH]}$COIN_CLI"
}

function configure_shared_directory() {
  # Create the shared blockchain directory if it doesn't exist
  if [[ ! -d $SHARED_DIR ]]; then
    mkdir -p "$SHARED_DIR/blocks" "$SHARED_DIR/chainstate"
  fi
}

function cmd_install() {
  # Install a new masternode instance
  # <$1 = instance_number>

  if [ ! -f "$COIN_FOLDER/$COIN_CONFIG" ]; then
    echo -e "$COIN_FOLDER/$COIN_CONFIG folder can't be found, $COIN_NAME is not installed in the system or the given profile has a wrong parameter"
    exit
  fi

  local new_folder="$COIN_FOLDER$1"

  mkdir -p $new_folder
  cp "$COIN_FOLDER/$COIN_CONFIG" $new_folder

  local new_user=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
  local new_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 22 | head -n 1)

  $(conf_set_value $new_folder/$COIN_CONFIG "rpcuser" "$new_user" 1)
  $(conf_set_value $new_folder/$COIN_CONFIG "rpcpassword" "$new_pass" 1)
  $(conf_set_value $new_folder/$COIN_CONFIG "rpcport" "$(find_port $RPC_PORT)" 1)
  $(conf_set_value $new_folder/$COIN_CONFIG "listen" 0 1)
  $(conf_set_value $new_folder/$COIN_CONFIG "masternodeprivkey" "$NEW_KEY" 1)

  # Symlink shared directories
  ln -s $SHARED_DIR/blocks $new_folder/blocks
  ln -s $SHARED_DIR/chainstate $new_folder/chainstate

  # Systemd service configuration
  configure_systemd $1
}

function configure_systemd() {
  # Configure the systemd service for the masternode instance
  # [$1 = instance_number]

  local service_name="$COIN_NAME-$1"

  echo -e "[Unit]\nDescription=$service_name service\nAfter=network.target\n\n[Service]\nUser=root\nGroup=root\nType=forking\nExecStart=$EXEC_COIN_DAEMON -daemon -conf=$COIN_FOLDER$1/$COIN_CONFIG -datadir=$COIN_FOLDER$1\nExecStop=$EXEC_COIN_CLI -conf=$COIN_FOLDER$1/$COIN_CONFIG -datadir=$COIN_FOLDER$1 stop\nRestart=always\nPrivateTmp=true\nTimeoutStopSec=60s\nTimeoutStartSec=10s\nStartLimitInterval=120s\nStartLimitBurst=5\n\n[Install]\nWantedBy=multi-user.target" > /etc/systemd/system/$service_name.service

  chmod +x /etc/systemd/system/$service_name.service
  systemctl daemon-reload
  systemctl enable $service_name.service &> /dev/null
  systemctl start $service_name.service
}

function main() {
  if [[ "$1" == "install" ]]; then
    load_profile $2
    configure_shared_directory
    cmd_install $3
  else
    echo "Usage: $0 install <profile_name> <instance_number>"
  fi
}

main "$@"
