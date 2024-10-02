#!/bin/bash

# Author: ElysiumRoyaleOfficial
# Source: https://github.com/ElysiumRoyale/ROYAL-MultiMN

# Modified to use shared blockchain data and single daemon instance.

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
COIN_PATH=""
COIN_SERVICE=""
EXEC_COIN_CLI=""
EXEC_COIN_DAEMON=""
IP=""
NEW_KEY=""
INSTALL_BOOTSTRAP=""

function echo_json() {
    [[ -t 3 ]] && echo -e "$1" >&3
}

function load_profile() {
    # <$1 = profile_name> | [$2 = check_exec]

    if [[ ! -f ".multimn/$1" ]]; then
        echo -e "${BLUE}$1${NC} profile hasn't been added"
        echo_json "{\"error\":\"profile hasn't been added\",\"errcode\":100}"
        exit
    fi

    local -A prof=$(get_conf .multimn/$1)
    local -A conf=$(get_conf .multimn/multimn.conf)

    local CMD_ARRAY=(COIN_NAME COIN_DAEMON COIN_CLI COIN_FOLDER COIN_CONFIG)
    for var in "${CMD_ARRAY[@]}"; do
        if [[ ! "${!prof[@]}" =~ "$var" || -z "${prof[$var]}" ]]; then
            echo -e "Missing required parameter ${MAGENTA}$var${NC} in profile ${GREEN}.multimn/$1${NC}"
            echo_json "{\"error\":\"profile missing parameter\",\"errcode\":101}"
            exit
        fi
    done
    if [[ ! "${!conf[@]}" =~ "$1" || -z "${conf[$1]}" || ! $(is_number "${conf[$1]}") ]]; then
        echo -e "Profile count missing or invalid in ${GREEN}.multimn/multimn.conf${NC}"
        echo_json "{\"error\":\"multimn.conf missing profile count\",\"errcode\":102}"
        exit
    fi

    PROFILE_NAME="$1"
    COIN_NAME="${prof[COIN_NAME]}"
    COIN_DAEMON="${prof[COIN_DAEMON]}"
    COIN_CLI="${prof[COIN_CLI]}"
    COIN_FOLDER="${prof[COIN_FOLDER]}"
    COIN_CONFIG="${prof[COIN_CONFIG]}"
    COIN_PATH="${prof[COIN_PATH]}"
    COIN_SERVICE="${prof[COIN_SERVICE]}"
    EXEC_COIN_DAEMON="${prof[COIN_PATH]}$COIN_DAEMON"
    EXEC_COIN_CLI="${prof[COIN_PATH]}$COIN_CLI"

    if [[ $2 -eq 1 ]]; then
        if [[ ! -f "$EXEC_COIN_DAEMON" ]]; then
            EXEC_COIN_DAEMON=$(which $COIN_DAEMON)
            if [[ ! -f "$EXEC_COIN_DAEMON" ]]; then
                echo -e "Can't locate ${GREEN}$COIN_DAEMON${NC}"
                echo_json "{\"error\":\"coin daemon can't be found\",\"errcode\":103}"
                exit
            fi
        fi
        if [[ ! -f "$EXEC_COIN_CLI" ]]; then
            EXEC_COIN_CLI=$(which $COIN_CLI)
            if [[ ! -f "$EXEC_COIN_CLI" ]]; then
                echo -e "Can't locate ${GREEN}$COIN_CLI${NC}"
                echo_json "{\"error\":\"coin cli can't be found\",\"errcode\":104}"
                exit
            fi
        fi
    fi
}

function get_conf() {
    # <$1 = conf_file>
    local str_map="";
    while IFS='=' read -r key value; do
        if [[ ! -z $key && ! -z $value ]]; then
            str_map+="[${key}]=${value} "
        fi
    done < "$1"
    echo -e "( $str_map )"
}

function is_number() {
    # <$1 = number>
    [[ "$1" =~ ^[0-9]+$ ]] && echo "1"
}

function configure_systemd() {
    cat << EOF > /etc/systemd/system/$COIN_SERVICE
[Unit]
Description=$COIN_NAME service
After=network.target
[Service]
User=$(whoami)
Group=$(whoami)
Type=forking
ExecStart=$EXEC_COIN_DAEMON -daemon -conf=$COIN_FOLDER/$COIN_CONFIG -datadir=$COIN_FOLDER
ExecStop=$EXEC_COIN_CLI -conf=$COIN_FOLDER/$COIN_CONFIG -datadir=$COIN_FOLDER stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF
    chmod +x /etc/systemd/system/$COIN_SERVICE
    systemctl daemon-reload
    systemctl enable $COIN_SERVICE
    systemctl start $COIN_SERVICE
}

function wallet_cmd() {
    # <$1 = start|stop|loaded> | [$2 = wait_timeout(loaded)]
    exec 2> /dev/null

    function wallet_loaded() {
        local timer=$([[ $1 ]] && echo $1 || echo 0)
        for (( i=0; i<=$timer; i++ )); do
            [[ $(is_number $($EXEC_COIN_CLI getblockcount)) ]] && echo "1" && break
            sleep 1
        done
    }

    case "$1" in
        "loaded")
            wallet_loaded $2
            ;;
        "start")
            if [[ ! $(wallet_loaded) ]]; then
                systemctl start $COIN_SERVICE &> /dev/null
                [[ $(wallet_loaded 30) ]] && echo "1"
            fi
            ;;
        "stop")
            if [[ $(wallet_loaded) ]]; then
                systemctl stop $COIN_SERVICE &> /dev/null
                [[ $($EXEC_COIN_CLI stop) ]] && sleep 3
                echo "1"
            fi
            ;;
    esac

    exec 2> /dev/tty
}

function conf_set_value() {
    # <$1 = conf_file> | <$2 = key> | <$3 = value> | [$4 = force_create]
    local key_line=$(grep -ws "^$2" "$1")
    if [[ "$(echo $key_line | cut -d '=' -f1)" == "$2" ]]; then
        sed -i "/^$2\s*=/c $2=$3" $1
    else
        [[ "$4" == "1" ]] && echo -e "$2=$3" >> $1
    fi
}

function conf_get_value() {
    # <$1 = conf_file> | <$2 = key>
    grep -ws "^$2" "$1" | cut -d "=" -f2
}

function cmd_profadd() {
    # <$1 = profile_file> | [$2 = profile_name]

    if [[ ! -f $1 ]]; then
        echo -e "${BLUE}$1${NC} file doesn't exist"
        echo_json "{\"error\":\"provided file doesn't exist\",\"errcode\":400}"
        return
    fi

    local -A prof=$(get_conf $1)
    local CMD_ARRAY=(COIN_NAME COIN_DAEMON COIN_CLI COIN_FOLDER COIN_CONFIG COIN_SERVICE COIN_PATH)

    for var in "${CMD_ARRAY[@]}"; do
        if [[ ! "${!prof[@]}" =~ "$var" ]]; then
            echo -e "${MAGENTA}$var${NC} doesn't exist in the supplied profile file"
            echo_json "{\"error\":\"missing variable: $var\",\"errcode\":401}"
            return
        elif [[ -z "${prof[$var]}" ]]; then
            echo -e "${MAGENTA}$var${NC} doesn't contain a value in the supplied profile file"
            echo_json "{\"error\":\"missing value: $var\",\"errcode\":402}"
            return
        fi
    done

    local prof_name=$([[ ! $2 ]] && echo ${prof[COIN_NAME]} || echo "$2")

    if [[ $prof_name == "multimn.conf" ]]; then
        echo -e "Invalid profile name."
        echo_json "{\"error\":\"reserved profile name\",\"errcode\":403}"
        return
    elif [[ ${prof_name:0:1} == "-" ]]; then
        echo -e "Profile name cannot start with a dash ${RED}-${NC} character"
        echo_json "{\"error\":\"reserved profile name\",\"errcode\":403}"
        return
    fi

    [[ ! -d ~/.multimn ]] && mkdir ~/.multimn
    [[ ! -f ~/.multimn/multimn.conf ]] && touch ~/.multimn/multimn.conf
    [[ $(conf_get_value ~/.multimn/multimn.conf $prof_name) ]] || $(conf_set_value ~/.multimn/multimn.conf $prof_name 0 1)

    cp $1 ~/.multimn/$prof_name

    local fix_path=${prof[COIN_PATH]}
    local fix_folder=${prof[COIN_FOLDER]}

    if [[ ${fix_path:${#fix_path}-1:1} != "/" ]]; then
        sed -i "/^COIN_PATH=/s/=.*/=\"${fix_path//"/"/"\/"}\/\"/" ~/.multimn/$prof_name
    fi
    if [[ ${fix_folder:${#fix_folder}-1:1} == "/" ]]; then
        fix_folder=${fix_folder::-1}
        sed -i "/^COIN_FOLDER=/s/=.*/=\"${fix_folder//"/"/"\/"}\"/" ~/.multimn/$prof_name
    fi

    echo -e "${BLUE}$prof_name${NC} profile successfully added."
    echo_json "{\"message\":\"profile successfully added\",\"retcode\":0}"
}

function cmd_install() {
    # Install masternode

    # Ensure masternodeprivkey is set in elysiumroyale.conf
    local mn_privkey=$(conf_get_value $COIN_FOLDER/$COIN_CONFIG masternodeprivkey)
    if [[ -z $mn_privkey ]]; then
        echo "masternodeprivkey not found in $COIN_CONFIG. Generating a dummy key..."
        # Temporarily remove masternode=1
        sed -i '/^masternode=1/d' $COIN_FOLDER/$COIN_CONFIG
        # Start the daemon
        $EXEC_COIN_DAEMON -daemon -conf=$COIN_FOLDER/$COIN_CONFIG -datadir=$COIN_FOLDER
        sleep 10
        # Generate dummy masternodeprivkey
        DUMMY_KEY=$($EXEC_COIN_CLI createmasternodekey)
        # Stop the daemon
        $EXEC_COIN_CLI stop
        sleep 5
        # Add masternode=1 and masternodeprivkey back to config
        echo "masternode=1" >> $COIN_FOLDER/$COIN_CONFIG
        echo "masternodeprivkey=$DUMMY_KEY" >> $COIN_FOLDER/$COIN_CONFIG
    fi

    # Ensure the daemon is running
    if ! pgrep -x "$COIN_DAEMON" > /dev/null; then
        echo "Starting $COIN_NAME daemon..."
        $EXEC_COIN_DAEMON -daemon -conf=$COIN_FOLDER/$COIN_CONFIG -datadir=$COIN_FOLDER
        sleep 10
    fi

    if [[ ! $NEW_KEY ]]; then
        NEW_KEY=$($EXEC_COIN_CLI createmasternodekey)
        if [[ -z $NEW_KEY ]]; then
            echo -e "Failed to generate masternode private key."
            echo_json "{\"error\":\"Failed to generate masternode private key\",\"errcode\":501}"
            exit
        fi
    fi

    # Add masternode to activemasternode.conf
    local ALIAS="mn$(($(wc -l < $COIN_FOLDER/activemasternode.conf 2>/dev/null || echo 0) + 1))"
    echo "$ALIAS $NEW_KEY" >> $COIN_FOLDER/activemasternode.conf

    # Ensure the systemd service exists
    if [ ! -f "/etc/systemd/system/$COIN_SERVICE" ]; then
        echo "Creating systemd service..."
        configure_systemd
    fi

    # Restart the daemon to pick up the new masternode
    systemctl restart $COIN_SERVICE

    echo -e "Masternode $ALIAS added with private key $NEW_KEY"

    # Update the masternode count
    local current_count=$(conf_get_value ~/.multimn/multimn.conf $PROFILE_NAME)
    local new_count=$(($current_count + 1))
    conf_set_value ~/.multimn/multimn.conf $PROFILE_NAME $new_count

    echo_json "{\"message\":\"Masternode added\",\"alias\":\"$ALIAS\",\"privkey\":\"$NEW_KEY\"}"
}

function cmd_uninstall() {
    # <$1 = alias>

    if [[ -z $1 ]]; then
        echo -e "Alias is required to uninstall a masternode."
        echo_json "{\"error\":\"Alias is required\",\"errcode\":600}"
        return
    fi

    # Remove masternode from activemasternode.conf
    sed -i "/^$1 /d" $COIN_FOLDER/activemasternode.conf

    # Restart the daemon to apply changes
    systemctl restart $COIN_SERVICE

    # Update the masternode count
    local current_count=$(conf_get_value ~/.multimn/multimn.conf $PROFILE_NAME)
    local new_count=$(($current_count - 1))
    conf_set_value ~/.multimn/multimn.conf $PROFILE_NAME $new_count

    echo -e "Masternode $1 has been uninstalled."
    echo_json "{\"message\":\"Masternode uninstalled\",\"alias\":\"$1\"}"
}

function cmd_list() {
    # List masternodes

    echo -e "Listing masternodes for profile ${BLUE}$PROFILE_NAME${NC}:"

    if [ ! -f "$COIN_FOLDER/activemasternode.conf" ]; then
        echo -e "No masternodes configured."
        echo_json "{\"masternodes\":[]}"
        return
    fi

    local masternodes=()
    while IFS=' ' read -r alias privkey; do
        echo -e "${GREEN}$alias${NC}: $privkey"
        masternodes+=("{\"alias\":\"$alias\",\"privkey\":\"$privkey\"}")
    done < "$COIN_FOLDER/activemasternode.conf"

    echo_json "{\"masternodes\":[$(IFS=,; echo "${masternodes[*]}")]}"
}

function cmd_help() {
    echo -e "Options:
  - ${YELLOW}multimn profadd <prof_file> [prof_name]          ${NC}Adds a profile.
  - ${YELLOW}multimn install <prof_name> [params...]          ${NC}Install a new masternode.
      ${YELLOW}[params...]${NC} list:
        ${GREEN}-p ${DARKCYAN}KEY${NC}, ${GREEN}--privkey=${DARKCYAN}KEY${NC} Set a user-defined masternode private key.
  - ${YELLOW}multimn uninstall <prof_name> <alias>            ${NC}Uninstall the specified masternode.
  - ${YELLOW}multimn list <prof_name>                         ${NC}List masternodes for the profile.
  - ${YELLOW}multimn help                                     ${NC}Display this help message."
}

function main() {

    if [[ ! $1 ]]; then
        echo -e "No command inserted, use ${YELLOW}multimn help${NC} to see all the available commands"
        echo_json "{\"error\":\"no command inserted\",\"errcode\":1}"
        return
    fi

    local curr_dir=$PWD
    cd ~

    case "$1" in
        "profadd")
            if [[ ! $2 ]]; then
                echo -e "${YELLOW}multimn profadd <prof_file> [prof_name]${NC} requires a profile file."
                exit
            fi
            cmd_profadd $2 $3
            ;;
        "install")
            if [[ ! $2 ]]; then
                echo -e "${YELLOW}multimn install <prof_name> [params...]${NC} requires a profile name."
                exit
            fi
            load_profile $2 1
            shift 2
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -p|--privkey)
                        NEW_KEY="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done
            cmd_install
            ;;
        "uninstall")
            if [[ ! $2 || ! $3 ]]; then
                echo -e "${YELLOW}multimn uninstall <prof_name> <alias>${NC} requires a profile name and alias."
                exit
            fi
            load_profile $2
            cmd_uninstall $3
            ;;
        "list")
            if [[ ! $2 ]]; then
                echo -e "${YELLOW}multimn list <prof_name>${NC} requires a profile name."
                exit
            fi
            load_profile $2
            cmd_list
            ;;
        "help")
            cmd_help
            ;;
        *)
            echo -e "Unrecognized parameter: ${RED}$1${NC}"
            echo -e "use ${YELLOW}multimn help${NC} to see all the available commands"
            echo_json "{\"error\":\"unknown command: $1\",\"errcode\":2}"
            ;;
    esac
}

main $@
