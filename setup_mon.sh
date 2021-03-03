#!/bin/bash
#shellcheck disable=SC2009,SC2034,SC2059,SC2206,SC2086,SC2015,SC2154
#shellcheck source=/dev/null

######################################
# User Variables - Change as desired #
# Common variables set in env file   #
######################################

NO_INTERNET_MODE="N"                        # To skip checking for auto updates or make outgoing connections to guild-operators github repository

#CNODE_IP=127.0.0.1                         # Default IP/FQDN or pass multiple as args comma delimited string with no whitespace e.g. host1.domain,host2.domain
#CNODE_PORT=12798                           # Default monitoring port used by node for metrics (can be edited in config.json on node)
#GRAFANA_HOST=0.0.0.0                       # Default IP address for Grafana (bind to server public interface)
#GRAFANA_PORT=5000                          # Default port used by Grafana
#PROM_HOST=127.0.0.1                        # Default Prometheus host (bind to localhost as only accessed by Grafana)
#PROM_PORT=9090                             # Default Prometheus port (only accessed by Grafana)
#NEXP_PORT=9091                             # Default Node Exporter port

#PROJ_PATH=/opt/cardano/monitoring          # Default install path
#TIMEZONE="Europe/London"                   # Default Timezone for promtail config file, change as needed for your server timezone
#BRANCH="master"                            # Default branch in repo

                                            # Default to a remote monitoring/cnHids installation
                                            # these can also be overridden by args
#INSTALL_MON=true                           # Install base monitoring (Prometheus/Grafana/Dashboards)
#INSTALL_CNHIDS=true                        # Install cnHids (Prometheus/Grafana/Dashboards/OSSEC server/Dependencies)
#INSTALL_NODE_EXP=false                     # Install Node Exporter for base OS metrics
#INSTALL_OSSEC_AGENT=false                  # Install OSSEC agents, used for remote agents (not needed on server)

#CURL_TIMEOUT=60                            # Maximum time in seconds that you allow the file download operation to take before aborting (Default: 60s)
#UPDATE_CHECK='Y'                           # Check if there is an updated version of prereqs.sh script to download
#SUDO='Y'                                   # Used by docker builds to disable sudo, leave unchanged if unsure.

######################################
# Do NOT modify code below           #
######################################

######################################
# Static Variables                   #
######################################
DEBUG="N"
SETUP_MON_VERSION=2.0.0

# version information
ARCHS=("darwin-amd64" "linux-amd64"  "linux-armv6")
TMP_DIR=$(mktemp -d "/tmp/cnode_monitoring.XXXXXXXX")
PROM_VER=2.24.1
GRAF_VER=7.4.0
NEXP_VER=1.0.1
OSSEC_VER=3.6.0
PROMTAIL_VER=2.1.0
LOKI_VER=2.1.0
OSSEC_METRICS_VER=0.1.0
NEXP="node_exporter"

dirs -c # clear dir stack
[[ -z "${BRANCH}" ]] && BRANCH="master"

# guildops URLs
REPO="https://github.com/cardano-community/guild-operators"
REPO_RAW="https://raw.githubusercontent.com/cardano-community/guild-operators"
URL_RAW="${REPO_RAW}/${BRANCH}"

# tokenised config file URLs
PROM_CONF_URL="https://raw.githubusercontent.com/cyber-russ/cnhids/main/prometheus.yml"
GRAF_CONF_URL="https://raw.githubusercontent.com/cyber-russ/cnhids/main/grafana-datasources.yaml"
PROMTAIL_CONF_URL="https://raw.githubusercontent.com/cyber-russ/cnhids/main/promtail.yaml"
LOKI_CONF_URL="https://raw.githubusercontent.com/cyber-russ/cnhids/main/loki-config.yaml"
OSSEC_CONF_URL="https://raw.githubusercontent.com/cyber-russ/cnhids/main/ossec.conf"
OSSEC_METRICS_CONF_URL=""

# performance dashboard URLs
SKY_DB_URL="https://raw.githubusercontent.com/Oqulent/SkyLight-Pool/master/Haskel_Node_SKY_Relay1_Dash.json"
IOHK_DB="cardano-application-dashboard-v2.json"
IOHK_DB_URL="https://raw.githubusercontent.com/input-output-hk/cardano-ops/master/modules/grafana/cardano/$IOHK_DB"
ADV_DB_URL="https://raw.githubusercontent.com/cyber-russ/adavault-dashboard/main/adv-dashboard-grafana.json"

# cnHids dashboard URL
CNHIDS_DB_URL="https://raw.githubusercontent.com/cyber-russ/cnhids/main/grafana-dashboard.json"

#Why is this export statement here?...presumably so spawned processes have access to vars? Check....
export CNODE_IP CNODE_PORT PROJ_PATH TMP_DIR

IP_ADDRESS=$(hostname -I)
echo "IP ADDRESS:$IP_ADDRESS"

#Override with defaults as needed...
[[ -z ${PROJ_PATH} ]] && PROJ_PATH=/opt/cardano/monitoring
[[ -z ${FORCE_OVERWRITE} ]] && FORCE_OVERWRITE='N'
[[ -z ${CNODE_IP} ]] && CNODE_IP=127.0.0.1
[[ -z ${GRAFANA_HOST} ]] && GRAFANA_HOST=0.0.0.0
[[ -z ${GRAFANA_PORT} ]] && GRAFANA_PORT=5000
[[ -z ${PROM_HOST} ]] && PROM_HOST=9090
[[ -z ${PROM_PORT} ]] && PROM_PORT=9090
[[ -z ${NEXP_PORT} ]] && NEXP_PORT=9091
[[ -z ${TIMEZONE} ]] && TIMEZONE="Europe/London"
[[ -z ${CURL_TIMEOUT} ]] && CURL_TIMEOUT=60
[[ -z ${UPDATE_CHECK} ]] && UPDATE_CHECK='Y'
[[ -z ${SUDO} ]] && SUDO='Y'

[[ -z ${INSTALL_MON} ]] && INSTALL_MON=true
[[ -z ${INSTALL_CNHIDS} ]] && INSTALL_CNHIDS=true
[[ -z ${INSTALL_NODE_EXP} ]] && INSTALL_NODE_EXP=false
[[ -z ${INSTALL_OSSEC_AGENT} ]] && INSTALL_OSSEC_AGENT=false


######################################################
# Functions                                          #
######################################################

get_input() {
  printf "%s (default: %s): " "$1" "$2" >&2; read -r answer
  if [ -z "$answer" ]; then echo "$2"; else echo "$answer"; fi
}

get_answer() {
  printf "%s (yes/no): " "$*" >&2; read -r answer
  while :
  do
    case $answer in
    [Yy]*)
      return 0;;
    [Nn]*)
      return 1;;
    *) printf "%s" "Please enter 'yes' or 'no' to continue: " >&2; read -r answer
    esac
  done
}

versionCheck() { printf '%s\n%s' "${1//v/}" "${2//v/}" | sort -C -V; } #$1=available_version, $2=installed_version


message () {
    echo -e "$*" >&2
    exit 127
}

get_idx () {
    case $OSTYPE in
        "darwin"*)
            IDX=0
        ;;
        "linux-gnu"*)
            if [[ $HOSTTYPE == *"x86_64"* ]]; then
                IDX=1
            elif [[ $HOSTTYPE == *"arm"* ]]; then
                IDX=2
            else
                message "The $HOSTTYPE  is not supported"
            fi
        ;;
        *)
            message "The \"$OSTYPE\" OS is not supported"
        ;;
    esac
    echo $IDX
}

dl() {
    DL_URL="${1}"
    OUTPUT="${TMP_DIR}/$(basename "$DL_URL")"
    shift

    case ${DL} in
        *"wget"*)
            wget --no-check-certificate --output-document="${OUTPUT}" "${DL_URL}";;
        *)
            ( cd "$TMP_DIR" && curl -JOL "$DL_URL" --silent );;
    esac
}

usage() {
  cat <<EOF >&2
setup_mon.sh version "${SETUP_MON_VERSION}"
Usage: $(basename "$0") [-d directory] [-i IP/FQDN[,IP/FQDN]] [-p port] [M|H|N|A]
Setup monitoring packages for cnTools (Prometheus, Grafana, Node Exporter,
and cnHids packages like OSSEC, Promtail, Loki).
There are no dependencies for this script.
-d directory      Top level directory where you'd like to deploy the packages:
                  prometheus , node exporter, grafana, ossec etc
                  (default directory is /opt/cardano/monitoring)
-i IP/hostname    IPv4 address(es) or a FQDN/DNS name(s) for remote cardano-node(s) (relay/bpn)
                  (check for hasPrometheus in config.json on node;
                  eg: 127.0.0.1 to make sure bound to 0.0.0.0 for remote monitoring)
                  to pass muliple nodes comma delimit e.g -i relay1.domain,relay2.domain,bpn.domain
                  (default is 127.0.0.1 or localhost)
-p port           Port at which your cardano-node(s) is exporting stats
                  check for hasPrometheus in config.json
                  (default=12798)
-[M|H|N|A]        Install specific configuration;
                  - [M]onitoring perfomance (Grafana/Prometheus)
                  - cn[H]ids monitoring (Grafana/Prometheus/OSSEC/Dependencies)
                  - [N]ode exporter (needed to report base O/S performance metrics)
                  - OSSEC [A]gent (needed to report to OSSEC server)
                  (upgrade option to be added- preserve monitoring data)
                  Recommended deployment patterns are:
                  1) Monitoring and agents installed on single cardano node.
                  2) Install monitoring remotely and install agents on nodes.
                  We recommend installing monitoring on a seperate instance
                  e.g. perf monitoring and HIDS connected to remote nodes;
                  ./setup_mon.sh -MH -i relay1.domain,bpn.domain
                  ...then install node exporter and OSSEC agents on relay1 and bpn cnode instances;
                  ./setup_mon.sh -NA
                  -M on remote server implies -N on nodes
                  -H on remote server implies -NA on nodes.
EOF
  exit 1
}

# General exit handler
cleanup () {
  [[ -n $1 ]] && err=$1 || err=$?
  [[ $err -eq 0 ]] && clear
  tput cnorm # restore cursor
  [[ -n ${exit_msg} ]] && echo -e "\n${exit_msg}\n" || echo -e "\nsetup_mon terminated, cleaning up...\n"
  $DBG rm -rf "$TMP_DIR"  #remove any tmp files
  tput sgr0  # turn off all attributes
  exit $err
}
trap cleanup HUP INT TERM
trap 'stty echo' EXIT

# Command     : myExit [exit code] [message]
# Description : gracefully handle an exit and restore terminal to original state
# Args        : 0=Clear terminal, 1+ Keep terminal state

myExit () {
  exit_msg="$2"
  cleanup "$1"
}


######################################################
# Check environment and args                         #
######################################################

if [[ "${DEBUG}" == "Y" ]]; then
  DBG=echo
else
  unset DBG
fi

CURL=$(command -v curl)
WGET=$(command -v wget)
DL=${CURL:=$WGET}
if  [ -z "$DL" ]; then
    myExit 3 'You need to have "wget" or "curl" to be installed\nand accessable by PATH environment to continue...\nExiting.'
fi

[[ "${SUDO}" = 'Y' ]] && sudo="sudo" || sudo=""
[[ "${SUDO}" = 'Y' && $(id -u) -eq 0 ]] && myExit 1 "Please run as non-root user."

# For who runs the script within containers and running it as root.
U_ID=$(id -u)
G_ID=$(id -g)

while getopts :i:p:d:MHNA: opt; do
  case ${opt} in
    i )
      IFS=',' read -ra CNODE_IP <<< "$OPTARG"
      ;;
    p ) CNODE_PORT="$OPTARG" ;;
    d ) PROJ_PATH="$OPTARG" ;;
    M ) INSTALL_MON=true
        ;;
    H ) INSTALL_CNHIDS=true
        ;;
    N ) INSTALL_NODE_EXP=true
        ;;
    A )
        #We should never need to install the agent with the servers
        INSTALL_OSSEC_AGENT=true
        INSTALL_CNHIDS=false
        INSTALL_MON=false
        ;;
    \? )
      usage
      exit
      ;;
  esac
done
shift "$((OPTIND -1))"

## Test code to show ags- remove?
if [ "$INSTALL_MON" = true ] ; then
    echo 'INSTALL_MON = true'
fi

if [ "$INSTALL_CNHIDS" = true ] ; then
    echo 'INSTALL_CNHIDS = true'
fi

if [ "INSTALL_OSSEC_AGENT" = true ] ; then
    echo 'INSTALL_OSSEC_AGENT = true'
fi

if [ "INSTALL_NODE_EXP" = true ] ; then
    echo 'INSTALL_MON = true'
fi

echo 'CNODE_IP'
for i in "${CNODE_IP[@]}"; do
    echo "$i"
done

if [[ "$INSTALL_CNHIDS" = true ]]; then
echo -e "
You have chosen to install cnHids and we still need to automate this part of the answer script
Recommended responses for OSSEC server and agent installs (hybrid installs server and agent)
   1- What kind of installation do you want (server, agent, local, hybrid or help)? server|agent
   2- Choose where to install the OSSEC HIDS [/var/ossec]:/var/ossec
   3.1- Do you want e-mail notification? (y/n) [y]: n
   3.2- Do you want to run the integrity check daemon? (y/n) [y]: y
   3.3- Do you want to run the rootkit detection engine? (y/n) [y]: y
   3.4- Do you want to enable active response? (y/n) [y]: n
   3.5- Do you want to enable remote syslog (port 514 udp)? (y/n) [y]: n

Once you have installed the server, you will need to install and register the agents
To Do: Add details here...

" >&2
fi

read -p "Press any key to continue..." -n1 -s
echo ""

#######################################################
# Version Check                                       #
#######################################################

# Check if setup_mon.sh update is available
PARENT="$(dirname $0)"
if [[ ${UPDATE_CHECK} = 'Y' ]] && curl -s -f -m ${CURL_TIMEOUT} -o "${PARENT}"/setup_mon.sh.tmp ${URL_RAW}/scripts/cnode-helper-scripts/setup_mon.sh 2>/dev/null; then
  TEMPL_CMD=$(awk '/^# Do NOT modify/,0' "${PARENT}"/setup_mon.sh)
  TEMPL2_CMD=$(awk '/^# Do NOT modify/,0' "${PARENT}"/setup_mon.sh.tmp)
  if [[ "$(echo ${TEMPL_CMD} | sha256sum)" != "$(echo ${TEMPL2_CMD} | sha256sum)" ]]; then
    if get_answer "A new version of setup_mon script is available, do you want to download the latest version?"; then
      cp "${PARENT}"/setup_mon.sh "${PARENT}/setup_mon.sh_bkp$(date +%s)"
      STATIC_CMD=$(awk '/#!/{x=1}/^# Do NOT modify/{exit} x' "${PARENT}"/setup_mon.sh)
      printf '%s\n%s\n' "$STATIC_CMD" "$TEMPL2_CMD" > "${PARENT}"/setup_mon.sh.tmp
      {
        mv -f "${PARENT}"/setup_mon.sh.tmp "${PARENT}"/setup_mon.sh && \
        chmod 755 "${PARENT}"/setup_mon.sh && \
        myExit 0 "\nUpdate applied successfully, please run setup_mon again!\n";
      } || {
        myExit 1 "Update failed!\n\nPlease manually download latest version of setup_mon.sh script from GitHub";
      }
    fi
  fi
fi


######################################################
# Main install routine                               #
######################################################

#Check whether the install path already exists and exit if so (this needs to change once upgrade is supported)
if [ -e "$PROJ_PATH" ]; then
    myExit 1 "The \"$PROJ_PATH\" directory already exists please move or delete it.\nExiting."
fi

#Figure out what O/S variant we are running on (need to check which ones are supported for all packages)
IDX=$(get_idx)

#Trap ctrl+c etc for graceful exit (needs some more work on exit code)
trap myExit  SIGHUP SIGINT SIGQUIT SIGTRAP SIGABRT SIGTERM

# Set up directories for installation
PROM_DIR="$PROJ_PATH/prometheus"
GRAF_DIR="$PROJ_PATH/grafana"
PROMTAIL_DIR="$PROJ_PATH/promtail"
LOKI_DIR="$PROJ_PATH/loki"
OSSEC_METRICS_DIR="$PROJ_PATH/ossec_metrics"
NEXP_DIR="$PROJ_PATH/exporters"
DASH_DIR="$PROJ_PATH/dashboards"
SYSD_DIR="$PROJ_PATH/systemd"

# Create base directory and set permissions
echo "CREATE BASE DIRECTORY: Start"
mkdir -p "$PROJ_PATH" 2>/dev/null
rc=$?
if [[ "$rc" != 0 ]]; then
  echo "NOTE: Could not create directory as $(whoami), attempting sudo .."
  sudo mkdir -p "$PROJ_PATH" || message "WARN:Could not create folder $PROJ_PATH , please ensure that you have access to create it"
  sudo chown "$(whoami)":"$(id -g)" "$PROJ_PATH"
  chmod 750 "$PROJ_PATH"
  echo "NOTE: No worries, sudo worked !! Moving on .."
fi
echo "CREATE BASE DIRECTORY: End"

# Set up URLs for downloads
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v$PROM_VER/prometheus-$PROM_VER.${ARCHS[IDX]}.tar.gz"
GRAF_URL="https://dl.grafana.com/oss/release/grafana-$GRAF_VER.${ARCHS[IDX]}.tar.gz"
NEXP_URL="https://github.com/prometheus/$NEXP/releases/download/v$NEXP_VER/$NEXP-$NEXP_VER.${ARCHS[IDX]}.tar.gz"
LOKI_URL="https://github.com/grafana/loki/releases/download/v$LOKI_VER/loki-${ARCHS[IDX]}.zip"
PROMTAIL_URL="https://github.com/grafana/loki/releases/download/v$PROMTAIL_VER/promtail-${ARCHS[IDX]}.zip"
OSSEC_URL="https://github.com/ossec/ossec-hids/archive/$OSSEC_VER.tar.gz"
OSSEC_METRICS_URL="https://github.com/slim-bean/ossec-metrics/archive/v$OSSEC_METRICS_VER.tar.gz"

echo "MAIN INSTALL SEQUENCE: Start"

#Base Monitoring start --->
if [[ "$INSTALL_MON" == true || "$INSTALL_CNHIDS" == true ]]; then
   echo "INSTALL MONITORING BASE LAYER: Start"
   PROM_SERVICE=true
   GRAF_SERVICE=true
   echo -e "Downloading base packages..." >&2
   echo -e "Downloading prometheus v$PROM_VER..." >&2
   $DBG dl "$PROM_URL"
   echo -e "Downloading grafana v$GRAF_VER..." >&2
   $DBG dl "$GRAF_URL"
   echo -e "Downloading grafana dashboard(s)..." >&2
   if [[ "$INSTALL_MON" = true ]]; then
      #Other dashboards seem out of date...
      #echo -e "  - SKYLight Monitoring Dashboard" >&2
      #$DBG dl "$SKY_DB_URL"
      #echo -e "  - IOHK Monitoring Dashboard" >&2
      #$DBG dl "$IOHK_DB_URL"
      echo -e "  - ADAvault Monitoring Dashboard" >&2
      $DBG dl "$ADV_DB_URL"
   fi
   if [[ "$INSTALL_CNHIDS" = true ]]; then
      echo -e "  - cnHids Dashboard" >&2
      $DBG dl "CNHIDS_DB_URL"
   fi

   echo -e "Configuring components" >&2
   # Create install dirs
   mkdir -p "$PROM_DIR" "$GRAF_DIR" "$DASH_DIR" "$SYSD_DIR"
   # Untar files (strip leading component of path)
   tar zxC "$PROM_DIR" -f "$TMP_DIR"/*prome*gz --strip-components 1
   tar zxC "$GRAF_DIR" -f "$TMP_DIR"/*graf*gz --strip-components 1
   # Add install code here
   # Get tokenised conf files from Github, and replace tokens
   # Setup Grafana config- register datasource
   echo "Registering Prometheus as datasource in Grafana.."
   $DBG dl "$GRAF_CONF_URL"
   sed -i "s+localhost:8080+$PROM_HOST:$PROM_PORT+" "$TMP_DIR"/grafana-datasources.yaml
   cp "$TMP_DIR"/grafana-datasources.yaml "$GRAF_DIR"//conf/provisioning/datasources/grafana-datasources.yaml
   # Fix grafana's datasource in dashboards
   sed -e "s#Prometheus#prometheus#g" "$TMP_DIR"/*.json -i
   cp -pr "$TMP_DIR"/*.json "$DASH_DIR/"
   #Fix grafana hostname reference in default.ini
   #Add extra default.ini fixes here
   HOSTNAME=$(hostname)
   sed -e "s/http_addr.*/http_addr = $GRAFANA_HOST/g" -e "s/http_port = 3000/http_port = $GRAFANA_PORT/g" "$GRAF_DIR"/conf/defaults.ini -i

   # Setup Prometheus config...append to conf file
   $DBG dl "$PROM_CONF_URL"
   #Loop for multiple nodes
   for i in "${CNODE_IP[@]}"; do
   cat >> "$TMP_DIR"/prometheus.yml <<EOF
    - job_name: '${i}_cardano_node'
      static_configs:
      - targets: ['$i:$CNODE_PORT']
    - job_name: '${i}_node_exporter'
      static_configs:
      - targets: ['$i:$NEXP_PORT']
EOF
   done
   #Check to see if we need add scrapes for cnHids
   if [[ "$INSTALL_CNHIDS" = true ]]; then
   cat >> "$TMP_DIR"/prometheus.yml <<EOF
    - job_name: 'ossec'
      static_configs:
      - targets: ['localhost:8080']
    - job_name: 'ossec-metrics'
      static_configs:
      - targets: ['localhost:7070']
    - job_name: 'loki'
      static_configs:
      - targets: ['localhost:3100']
EOF
   fi
   cp "$TMP_DIR"/prometheus.yml "$PROM_DIR"

   # Change icons - change these to your icons, example for ADAvault
   # Add code here

   #provision the dashboards
   cat > "$GRAF_DIR"/conf/provisioning/dashboards/guildops.yaml <<EOF
   # config file version
   apiVersion: 1

   providers:
   - name: 'GuildOps'
     orgId: 1
     folder: ''
     folderUid: ''
     type: file
      options:
       path: $DASH_DIR
EOF
   echo "INSTALL MONITORING BASE LAYER: End"
fi
#<---Base Monitoring end

#cnHids Server/Agents start --->
#Fetch OSSEC for cnHids server and agents installs
if [[ "$INSTALL_CNHIDS" == true || "$INSTALL_OSSEC_AGENTS" == true ]] ; then
   echo "INSTALL CNHIDS SERVER: Start"
   #prereqs for OSSEC- move into prereqs?
   sudo apt install gcc make libevent-dev zlib1g-dev libssl-dev libpcre2-dev wget tar unzip -y
   echo -e "Downloading OSSEC server/agent" >&2
   $DBG dl "$OSSEC_URL"
   # Install OSSEC server
   # Is it possible to remove the manual choices? Can we provide an answer file? For now we just launch
   tar zxC "$TMP_DIR" -f "$TMP_DIR"/ossec-hids*gz
   #Follow the prompts to install server version of OSSEC
   sudo "$TMP_DIR"/ossec-hids-"$OSSEC_VER"/install.sh
   #Get the conf file, apply then restart
   $DBG dl "$OSSEC_CONF_URL"
   sudo cp "$TMP_DIR"/ossec.conf /var/ossec/etc/ossec.conf
   sudo /var/ossec/bin/ossec-control restart
   echo "INSTALL CNHIDS SERVER: End"
fi
#<---cnHids Server/Agents end

#cnHids Dependencies start --->
if [[ "$INSTALL_CNHIDS" = true ]] ; then
   echo "INSTALL CNHIDS DEPENDENCIES: Start"
   PROMTAIL_SERVICE=true
   LOKI_SERVICE=true
   OSSEC_METRICS_SERVICE=true
   echo -e "Downloading cnHids packages..." >&2
   $DBG dl "$PROMTAIL_URL"
   $DBG dl "$LOKI_URL"
   $DBG dl "$OSSEC_METRICS_URL"

   echo -e "Configuring components" >&2
   # Create install dirs
   mkdir -p "$PROMTAIL_DIR" "$LOKI_DIR" "$OSSEC_METRICS_DIR"
   # Unzip files (strip leading component of path)
   #unzip -d "$PROMTAIL_DIR" "$TMP_DIR"/*promta*zip && f=("$PROMTAIL_DIR"/*) && mv "$PROMTAIL_DIR"/*/* "$PROMTAIL_DIR" && rmdir "${f[@]}"
   unzip "$TMP_DIR/promtail-${ARCHS[IDX]}.zip" -d "$PROMTAIL_DIR"
   unzip "$TMP_DIR/loki-${ARCHS[IDX]}.zip" -d "$LOKI_DIR"
   tar zxC "$TMP_DIR" -f "$TMP_DIR"/ossec-metrics*gz
   # Set as executable
   chmod +x "$PROMTAIL_DIR/promtail-${ARCHS[IDX]}"
   chmod +x "$LOKI_DIR/loki-${ARCHS[IDX]}"
   # Get tokenised conf files from Github, and replace tokens
   # Promtail
   $DBG dl "$PROMTAIL_CONF_URL"
   sed -i 's+Europe/London+$TIMEZONE+' "$TMP_DIR"/$(basename "$PROMTAIL_CONF_URL")
   cp "$TMP_DIR"/$(basename "$PROMTAIL_CONF_URL") "$PROMTAIL_DIR"
   # Loki
   $DBG dl "$LOKI_CONF_URL"
   sed -i 's+/opt/cardano/monitoring+$PROJ_PATH+g' "$TMP_DIR"/$(basename "$LOKI_CONF_URL")
   cp "$TMP_DIR"/$(basename "$LOKI_CONF_URL") "$LOKI_DIR"
   # OSSEC-metrics
   sudo apt install golang-go
   cd "$TMP_DIR"/ossec-metrics-"$OSSEC_METRICS_VER"/
   go build -o ossec-metrics cmd/ossec-metrics/main.go
   chmod +x ossec-metrics
   mv ossec-metrics "$OSSEC_METRICS_DIR"
   echo "INSTALL CNHIDS DEPENDENCIES: End"
fi
#<---cnHids Dependencies end

#Node exporter start --->
if [[ "$INSTALL_NODE_EXP" = true ]] ; then
   echo "INSTALL NODE EXPORTER: Start"
   NEXP_SERVICE=true
   echo -e "Downloading exporter v$NEXP_VER..." >&2
   $DBG dl "$NEXP_URL"

   echo -e "Configuring components" >&2
   # Create install dirs
   mkdir -p "$NEXP_DIR" "$SYSD_DIR"
   # Untar files (strip leading component of path)
   tar zxC "$TMP_DIR" -f "$TMP_DIR"/*node_exporter*gz --strip-components 1
   # Move to destination and set as executable
   mv "$TMP_DIR/node_exporter" "$NEXP_DIR/"
   chmod +x "$NEXP_DIR"/*
   # Add install code here
   # Get tokenised conf files from Github, and replace tokens
   echo "INSTALL NODE EXPORTER: End"
fi
#<---Node Exporter end

######################################################
# Set up the service definitions for systemd         #
######################################################

#Promtail start --->
if [[ "$PROMTAIL_SERVICE" = true ]] ; then
   echo "INSTALL PROMTAIL SERVICE: Start"
   cat > "$SYSD_DIR"/promtail.service <<EOF
[Unit]
Description=Promtail Loki Agent
After=loki.service

[Service]
Type=simple
User=root
ExecStart=$PROMTAIL_DIR/promtail-linux-amd64 -config.file promtail.yaml
WorkingDirectory=$PROMTAIL_DIR
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

   #Copy over the files and start services
   echo "INSTALL PROMTAIL SERVICE: copying definition and starting"
   sudo cp "$SYSD_DIR"/promtail.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable promtail
   sudo systemctl start promtail
   echo "INSTALL PROMTAIL SERVICE: End"
else
   sudo systemctl disable promtail
fi
#<---Promtail end

#LOKI start --->
if [[ "$LOKI_SERVICE" = true ]] ; then
   echo "INSTALL LOKI SERVICE: Start"
   cat > "$SYSD_DIR"/loki.service <<EOF
[Unit]
Description=Loki Log Aggregator
After=network.target

[Service]
Type=simple
User=cnhids
ExecStart=$LOKI_DIR/loki-linux-amd64 -config.file loki-config.yaml
WorkingDirectory=$LOKI_DIR
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

   #Copy over the files and start services
   echo "INSTALL LOKI SERVICE: copying definition and starting"
   sudo cp "$SYSD_DIR"/loki.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable loki
   sudo systemctl start loki
   echo "INSTALL LOKI SERVICE: End"
else
   sudo systemctl disable loki
fi
#<---LOKI end

#OSSEC_METRICS start --->
if [[ "$OSSEC_METRICS_SERVICE" = true ]] ; then
   echo "INSTALL OSSEC_METRICS SERVICE: Start"
   cat > "$SYSD_DIR"/ossec-metrics.service <<EOF
[Unit]
Description=Ossec Metrics exposes OSSEC info for prometheus to scrape
After=network.target

[Service]
Type=simple
User=root
ExecStart=$OSSEC_METRICS_DIR/ossec-metrics
WorkingDirectory=$OSSEC_METRICS
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

   #Copy over the files and start services
   echo "INSTALL OSSEC_METRICS SERVICE: copying definition and starting"
   sudo cp "$SYSD_DIR"/ossec-metrics.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable ossec-metrics
   sudo systemctl start ossec-metrics
   echo "INSTALL OSSEC_METRICS SERVICE: End"
else
   sudo systemctl disable ossec-metrics
fi
#<---OSSEC_METRICS end

#Prometheus start --->
   if [[ "$PROM_SERVICE" = true ]] ; then
   echo "INSTALL PROMETHEUS SERVICE: Start"
   cat > "$SYSD_DIR"/prometheus.service <<EOF
[Unit]
Description=Prometheus Server
Documentation=https://prometheus.io/docs/introduction/overview/
After=network-online.target

[Service]
User=$(whoami)
Restart=on-failure
ExecStart=$PROM_DIR/prometheus \
  --config.file=$PROM_DIR/prometheus.yml \
  --storage.tsdb.path=$PROM_DIR/data --web.listen-address=$PROM_HOST:$PROM_PORT
WorkingDirectory=$PROM_DIR
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF

   #Copy over the files and start services
   echo "INSTALL PROMETHEUS SERVICE: copying definition and starting"
   sudo cp "$SYSD_DIR"/prometheus.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable prometheus
   sudo systemctl start prometheus
   echo "INSTALL PROMETHEUS SERVICE: End"
else
   sudo systemctl disable prometheus
fi
#<---Prometheus end

#Node Exporter --->
   if [[ "$NEXP_SERVICE" = true ]] ; then
   echo "INSTALL NODE EXPORTER SERVICE: Start"
   cat > "$SYSD_DIR"/node-exporter.service <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=$(whoami)
Restart=on-failure
ExecStart=$NEXP_DIR/node_exporter --web.listen-address="$CNODE_IP:$NEXP_PORT"
WorkingDirectory=$NEXP_DIR
LimitNOFILE=3500

[Install]
WantedBy=default.target
EOF

   #Copy over the files and start services
   echo "INSTALL NODE EXPORTER SERVICE: copying definitions and starting"
   sudo cp "$SYSD_DIR"/node-exporter.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable node-exporter
   sudo systemctl start node-exporter
   echo "INSTALL NODE EXPORTER SERVICE: End"
else
   sudo systemctl disable node-exporter
fi
#<---Node Exporter end

#Grafana start --->
   if [[ "$GRAF_SERVICE" = true ]] ; then
   echo "INSTALL GRAFANA SERVICE: Start"
   cat > "$SYSD_DIR"/grafana.service <<EOF
[Unit]
Description=Grafana instance
Documentation=http://docs.grafana.org
Wants=network-online.target
After=network-online.target

[Service]
User=$(whoami)
Restart=on-failure
ExecStart=$GRAF_DIR/bin/grafana-server web
WorkingDirectory=$GRAF_DIR
LimitNOFILE=10000

[Install]
WantedBy=default.target
EOF

   #Copy over the files and start services
   echo "INSTALL GRAFANA SERVICE: copying definitions and starting"
   sudo cp "$SYSD_DIR"/grafana.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable grafana
   sudo systemctl start grafana
   echo "INSTALL GRAFANA SERVICE: End"
else
   sudo systemctl disable grafana
fi
#<---Grafana end

echo "MAIN INSTALL SEQUENCE: End"

#############################################
# Finish the install
#############################################

#Make the output conditional based on what was selected

echo -e "
=====================================================
INSTALLATION: Completed
=====================================================
" >&2

if [[ "$INSTALL_MON" = true ]]; then
echo -e "
Base Monitoring layer installed:
- Prometheus    : http://$PROM_HOST:$PROM_PORT/metrics
- Grafana       : http://$IP_ADDRESS:$GRAFANA_PORT
- cnode metrics : http://$CNODE_IP:$CNODE_PORT

You need to do the following to configure grafana:
0. The services should already be started, verify if you can login to grafana, and prometheus.
You can check via curl at the addresses above (127.0.0.1 will not allow remote access)
1. Login to grafana as admin/admin (http://$IP_ADDRESS:$GRAFANA_PORT)
2. A \"prometheus\" (all lowercase) datasource has been added (http://$PROM_HOST:$PROM_PORT)
3. A base dashboard has been provisioned or import an existing dashboard (left plus sign).
  - Sometimes, the individual panel's \"prometheus\" datasource needs to be refreshed.
" >&2
fi

if [[ "$INSTALL_CNHIDS" = true ]]; then
echo -e "
cnHids installed and services running:
- To start OSSEC HIDS: /var/ossec/bin/ossec-control start
- To stop OSSEC HIDS: /var/ossec/bin/ossec-control stop
- The configuration can be viewed or modified at /var/ossec/etc/ossec.conf
You will need to install agents on any remote endpoints (-A option)
You can access the cnHids dashboard via grafana (http://$IP_ADDRESS:$GRAFANA_PORT)
" >&2
fi

if [[ "$INSTALL_OSSEC_AGENTS" = true ]]; then
echo -e "
OSSEC agent installed and services running for cnHids:
- To start OSSEC agent: /var/ossec/bin/ossec-control start
- To stop OSSEC agent: /var/ossec/bin/ossec-control stop
- The configuration can be viewed or modified at /var/ossec/etc/ossec.conf
You will need to restart the OSSEC server for the first agent installed
Make sure you have port 1514 UDP open from agent to server on any firewalls
" >&2
fi

if [[ "$INSTALL_NODE_EXP" = true ]]; then
echo -e "
Node Exporter installed:
- Node exp metrics:   http://$CNODE_IP:$NEXP_PORT
" >&2
fi

myExit 1 "END: Thanks for watching. This has been a GuildOps Production."

