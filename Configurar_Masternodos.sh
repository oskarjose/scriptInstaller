#!/bin/bash
CONFIG_FILE='threadcoin.conf'
COIN_DAEMON='threadcoind'
COIN_CLI='threadcoin-cli'
COIN_PATH='/usr/local/bin/'
COIN_REPO='https://github.com/ThreadCoinDev/threadcoin.git'
COIN_TGZ='https://github.com/ThreadCoinDev/threadcoin/releases/download/v1.0.0.0/threadcoin_v1.0.0.0_linux64.tar.gz'
COIN_ZIP=$(echo $COIN_TGZ | awk -F'/' '{print $NF}')
COIN_NAME='threadcoin'
COIN_PORT=7419
NODEIP=$(curl -s4 icanhazip.com)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

function checks() {
  if [[ $(lsb_release -d) != *16.04* ]]; then
    echo -e "${RED}You are not running Ubuntu 16.04. Installation is cancelled.${NC}"
    exit 1
  fi
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}$0 must be run as root.${NC}"
    exit 1
  fi
  if [ -n "$(pidof $COIN_DAEMON)" ] || [ -e "$COIN_DAEMOM" ] ; then
    echo -e "${RED}$COIN_NAME is already installed.${NC}"
    exit 1
  fi
}

function download_node() {
  echo -e "${GREEN}Downloading and Installing VPS $COIN_NAME Daemons...${NC}"
  wget -q $COIN_TGZ
  tar -xzvf $COIN_ZIP 
  chmod u+x threadcoin/bin/threadcoind 
  chmod u+x threadcoin/bin/threadcoin-cli
  chmod u+x threadcoin/bin/threadcoin-qt
  chmod u+x threadcoin/bin/threadcoin-tx
  cp threadcoin/bin/threadcoind $COIN_PATH
  cp threadcoin/bin/threadcoin-cli $COIN_PATH
  cp threadcoin/bin/threadcoin-qt $COIN_PATH
  cp threadcoin/bin/threadcoin-tx $COIN_PATH
}

function get_ip() {
  declare -a NODE_IPS
  for ips in $(netstat -i | awk '!/Kernel|Iface|lo/ {print $1," "}')
  do
    NODE_IPS+=($(curl --interface $ips --connect-timeout 2 -s4 icanhazip.com))
  done
  if [ ${#NODE_IPS[@]} -gt 1 ]
    then
      echo -e "${GREEN}More than one IP. Please type 0 to use the first IP, 1 for the second and so on...${NC}"
      INDEX=0
      for ip in "${NODE_IPS[@]}"
      do
        echo ${INDEX} $ip
        let INDEX=${INDEX}+1
      done
      read -e choose_ip
      NODEIP=${NODE_IPS[$choose_ip]}
  else
    NODEIP=${NODE_IPS[0]}
  fi
}


function create_config() {
echo -e "${GREEN}Creating Config File...${NC}"
mkdir -p "$HOME/.threadcoincore/"
RPCUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
RPCPASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)
cat << EOF > "$HOME/.threadcoincore/$CONFIG_FILE"
rpcuser=$RPCUSER
rpcpassword=$RPCPASSWORD
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
port=$COIN_PORT
EOF
}


function create_key() {
  $COIN_DAEMON -daemon
  sleep 30
  if [ -z "$(ps axo cmd:100 | grep $COIN_DAEMON)" ]; then
    echo -e "${RED}$COIN_NAME server couldn not start. Check /var/log/syslog for errors.{$NC}"
    exit 1
  fi
  COINKEY=$($COIN_CLI masternode genkey)
  if [ "$?" -gt "0" ];
    then
    echo -e "${RED}Wallet not fully loaded. Let us wait and try again to generate the Private Key${NC}"
    sleep 30
    COINKEY=$($COIN_CLI masternode genkey)
  fi
  $COIN_CLI stop
}

function update_config() {
sed -i 's/daemon=1/daemon=0/' "$HOME/.threadcoincore/$CONFIG_FILE"
cat << EOF >> "$HOME/.threadcoincore/$CONFIG_FILE"
logintimestamps=1
maxconnections=256
masternode=1
externalip=$NODEIP:$COIN_PORT
masternodeprivkey=$COINKEY
EOF
}
function enable_firewall() {
  echo -e "${GREEN}Installing and setting up firewall to allow ingress on port $COIN_PORT...${NC}"
  ufw allow $COIN_PORT/tcp comment "$COIN_NAME MN port" >/dev/null
  ufw allow ssh comment "SSH" 
  ufw limit ssh/tcp 
  ufw default allow outgoing 
  echo "y" | ufw enable 
}

function Masternode_Configuration() {
echo -e "${GREEN}Creating masternodes config file...${NC}"
MNUSER=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 5 | head -n 1)
cat << EOF >> "masternode.conf"
$MNUSER $NODEIP:$COIN_PORT $COINKEY $(cat txoutputs)
EOF
$COIN_DAEMON -daemon
}

function important_information() {
 echo
 echo -e "================================================================================================================================"
 echo -e "$COIN_NAME Masternode is up and running listening on port ${GREEN}$COIN_PORT${NC}."
 echo -e "Configuration file is: ${RED}$CONFIGFOLDER/$CONFIG_FILE${NC}"
 echo -e "Masternode Config is: $MNUSER $NODEIP:$COIN_PORT $COINKEY "$(cat txoutputs)
 echo -e "VPS_IP:PORT ${RED}$NODEIP:$COIN_PORT${NC}"
 echo -e "MASTERNODE PRIVATEKEY is: ${RED}$COINKEY${NC}"
 echo -e "Start: ${RED}threadcoind & ${NC}"
 echo -e "Stop: ${RED}threadcoin-cli stop ${NC}"
 echo -e "Please check ${GREEN}$COIN_NAME${NC} is running with the following command: ${GREEN}threadcoin-cli masternode status ${NC}"
 echo -e "================================================================================================================================"
}

function configure_systemd() {
echo -e "${GREEN}Configuring $COIN_NAME service...${NC}"
cat << EOF > /etc/systemd/system/$COIN_NAME.service
[Unit]
Description=$COIN_NAME service
After=network.target
[Service]
User=root
Group=root
Type=forking
ExecStart=/usr/local/bin/threadcoind -daemon -conf=/root/.threadcoincore/threadcoin.conf -datadir=/root/.threadcoincore
ExecStop=/usr/local/bin/threadcoind-cli stop
Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=30s
StartLimitInterval=120s
StartLimitBurst=5
[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  sleep 3
  systemctl start $COIN_NAME.service
  systemctl enable $COIN_NAME.service 

  if [[ -z "$(ps axo cmd:100 | egrep $COIN_DAEMON)" ]]; then
    echo -e "${RED}$COIN_NAME is not running${NC}, please investigate. You should start by running the following commands as root:"
    echo -e "${GREEN}systemctl start $COIN_NAME.service"
    echo -e "systemctl status $COIN_NAME.service"
    echo -e "less /var/log/syslog${NC}"
    exit 1
  fi
}


function setup_node() {
  get_ip
  create_config
  create_key
  update_config
  enable_firewall
  #configure_systemd
  Masternode_Configuration
  important_information
}



##### Main #####
checks
download_node
setup_node






