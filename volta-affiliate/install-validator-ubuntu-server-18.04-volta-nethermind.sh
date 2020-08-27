#!/bin/bash

# Make the script exit on any error
set -e
set -o errexit
DEBIAN_FRONTEND=noninteractive

# Configuration Block - Docker checksums are the image Id
export NETHERMIND_VERSION="nethermind/nethermind:1.8.89"
NETHERMIND_CHKSUM="sha256:6f92d584e6188932a0683948447e2d14824418e3a3443ca7d30ea7c29309bfaa"

export NETHERMINDTELEMETRY_VERSION="1.0.0"
NETHERMINDTELEMETRY_CHKSUM="sha256:3ef12c74dcc3bfe67efc54f30ffea8400ce83e932d8ba38a2989c5cf65008987"

TELEGRAF_VERSION="1.15.2"
TELEGRAF_CHKSUM="b539ed52df8ec63258ea97e91cc1145333b0345bca3f5863bebfca60df6f46e9  telegraf_1.15.2-1_amd64.deb"

# Chain/Nethermind configuration
export CHAINNAME="volta"
BLOCK_GAS="8000000"
CHAINSPEC_URL="https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/master/Volta.json"
NLOG_CONFIG="https://raw.githubusercontent.com/NethermindEth/nethermind/master/src/Nethermind/Nethermind.Runner/NLog.config"

# Make sure locales are properly set and generated
apt-get update -y
apt-get install locales -y
echo "Setup locales"
cat > /etc/locale.gen << EOF
de_DE.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
locale-gen
echo -e 'LANG="en_US.UTF-8"\nLANGUAGE="en_US:en"\n' > /etc/default/locale
source /etc/default/locale

# Try to guess the current primary network interface
NETIF="$(ip route | grep default | awk '{print $5}')"

# Install system updates and required tools and dependencies
echo "Installing dependencies"

# Preparing iptables auto-save
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

apt-get install -y curl net-tools dnsutils expect jq iptables-persistent debsums chkrootkit moreutils

# Collecting information from the user

# Get external IP
if [ -f /sys/hypervisor/uuid ] && [ `head -c 3 /sys/hypervisor/uuid` == ec2 ]; then
    EXTERNAL_IP="$(dig @resolver1.opendns.com ANY myip.opendns.com +short)"
else
    EXTERNAL_IP="$(ip -o route get to 8.8.8.8 | sed -n 's/.*src \([0-9.]\+\).*/\1/p')"
fi

if [ ! "$1" == "--auto" ];
then
# Show a warning that SSH login is restriced after install finishes
whiptail --backtitle="EWF Genesis Node Installer" --title "Warning" --yes-button "Continue" --no-button "Abort" --yesno "After the installation is finished you can only login through SSH with the current user on port 2222 and the key provided in the next steps." 10 60
HOMEDIR=$(pwd)
# Confirm user home directory
whiptail --backtitle="EWF Genesis Node Installer" --title "Confirm Home Directory" --yesno "Is $(pwd) the normal users home directory?" 8 60

until [[ -n "$COMPANY_NAME" ]]; do
	      COMPANY_NAME=$(whiptail --backtitle="EWF Genesis Node Installer" --inputbox "Enter Affiliate/Company Name (will be cut to 30 chars)" 8 78 $COMPANY_NAME --title "Node Configuration" 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [[ $exitstatus = 0 ]]; then
                echo "Affiliate/Company name has been set to: " $COMPANY_NAME
        else
                echo "User has cancelled the prompt."
                break;
        fi
done

EXTERNAL_IP=$(whiptail --backtitle="EWF Genesis Node Installer" --inputbox "Enter this hosts public IP" 8 78 $EXTERNAL_IP --title "Connectivity" 3>&1 1>&2 2>&3)
NETIF=$(whiptail --backtitle="EWF Genesis Node Installer" --inputbox "Enter this hosts primary network interface" 8 78 $NETIF --title "Connectivity" 3>&1 1>&2 2>&3)
fi

COMPANY_NAME=$(echo $COMPANY_NAME | cut -c -30)

# Declare a main function. This way we can put all other functions (especially the assert writers) to the bottom.
main() {

# Secure SSH by disable password login and only allowing login as user with keys. Also shifts SSH port from 22 to 2222
echo "Securing SSH..."
writeSShConfig
service ssh restart

# Add more DNS servers (cloudflare and google) than just the DHCP one to increase DNS resolve stability
echo "Add more DNS servers"
echo "dns-nameservers 8.8.8.8 1.1.1.1" >> /etc/network/interfaces
echo "nameserver 1.1.1.1" >> /etc/resolv.conf
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Disable the DHPC clients ability to overwrite resolv.conf
echo 'make_resolv_conf() { :; }' > /etc/dhcp/dhclient-enter-hooks.d/leave_my_resolv_conf_alone
chmod 755 /etc/dhcp/dhclient-enter-hooks.d/leave_my_resolv_conf_alone

# Install current stable Docker
echo "Install Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
chmod +x get-docker.sh
./get-docker.sh
rm get-docker.sh

# Write docker config
writeDockerConfig
service docker restart

# Install docker-compose
echo "install compose"
curl -L "https://github.com/docker/compose/releases/download/1.26.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose

# Install the Telegrad telemetry collector
echo "Install Telegraf..."
wget https://dl.influxdata.com/telegraf/releases/telegraf_$TELEGRAF_VERSION-1_amd64.deb

# Verify
TG_CHK="$(sha256sum telegraf_$TELEGRAF_VERSION-1_amd64.deb)"
if [ "$TELEGRAF_CHKSUM" != "$TG_CHK" ]; then
  echo "ERROR: Unable to verify telegraf package. Checksum missmatch."
  exit -1;
fi

dpkg -i telegraf_$TELEGRAF_VERSION-1_amd64.deb
rm telegraf_$TELEGRAF_VERSION-1_amd64.deb
usermod -aG docker telegraf

# Stop telegraf as it won't be able to write telemetry until the signer is running.
service telegraf stop

# Prepare and pull docker images and verify their checksums
echo "Prepare Docker..."

mkdir -p ~/.docker
cat > ~/.docker/config.json << EOF
{
    "HttpHeaders": {
        "User-Agent": "Docker-Client/18.09.4 (linux)"
    }
}
EOF
docker pull $NETHERMIND_VERSION

# verify image
IMGHASH="$(docker image inspect $NETHERMIND_VERSION|jq -r '.[0].Id')"
if [ "$NETHERMIND_CHKSUM" != "$IMGHASH" ]; then
  echo "ERROR: Unable to verify nethermind docker image. Checksum missmatch."
  exit -1;
fi

docker pull nethermindeth/nethermind-telemetry:$NETHERMINDTELEMETRY_VERSION
IMGHASH="$(docker image inspect nethermindeth/nethermind-telemetry:$NETHERMINDTELEMETRY_VERSION|jq -r '.[0].Id')"
if [ "$NETHERMINDTELEMETRY_CHKSUM" != "$IMGHASH" ]; then
  echo "ERROR: Unable to verify nethermind-telemetry docker image. Checksum missmatch."
  exit -1;
fi

# Create the directory structure
mkdir docker-stack
chmod 750 docker-stack
cd docker-stack
mkdir chainspec
mkdir database
mkdir configs
mkdir logs
mkdir keystore

echo "Fetch Chainspec..."
# TODO: replace with chainspec location
wget $CHAINSPEC_URL -O chainspec/volta.json

echo "Creating Account..."

# Generate random account password and store
XPATH="$(pwd)"
PASSWORD="$(openssl rand -hex 32)"
echo "$PASSWORD" > .secret
chmod 400 .secret
chown 1000:1000 .secret
mv .secret keystore/.secret

docker run -d --network host --name nethermind \
    -v ${XPATH}/keystore/:/nethermind/keystore \
    ${NETHERMIND_VERSION} --config ${CHAINNAME} --Init.EnableUnsecuredDevWallet true --JsonRpc.Enabled true
    
generate_account_data() 
{
cat << EOF
{ "method": "personal_newAccount", "params": ["$PASSWORD"], "id": 1, "jsonrpc": "2.0" }
EOF
}

echo "Waiting 30 sec for nethermind to come up and create an account..."
sleep 30
# Send request to create account from seed
ADDR=`curl --request POST --url http://localhost:8545/ --header 'content-type: application/json' --data "$(generate_account_data)" | jq -r '.result'`

echo "Account created: $ADDR"
INFLUX_USER=${ADDR:2} # cutting 0x prefix
INFLUX_PASS="$(openssl rand -hex 16)"


# got the key now discard of the nethermind instance
docker stop nethermind
docker rm -f nethermind

writeNethermindConfig
NETHERMIND_KEY_FILE="$(ls -1 ./keystore/|grep UTC|tail -n1)"

# Prepare nethermind telemetry pipe
mkfifo /var/spool/nethermind.sock
chown telegraf /var/spool/nethermind.sock

# Write NLog config file
wget $NLOG_CONFIG -O NLog.config
setJsonRpcLogsLevelToError

# Write the docker-compose file to disk
writeDockerCompose

# start everything up
docker-compose up -d

# Collect the enode from nethermind over RPC

echo "Waiting 15 sec for nethermind to come up and generate the enode..."
sleep 15
ENODE=`curl -s --request POST --url http://localhost:8545/ --header 'content-type: application/json' --data '{ "method": "net_localEnode", "params": [], "id": 1, "jsonrpc": "2.0" }' | jq -r '.result'`

# Now all information is complete to write the telegraf file
writeTelegrafConfig
service telegraf restart

echo "Setting up firewall"

# non-docker services
iptables -F INPUT
iptables -F DOCKER-USER || true
iptables -X FILTERS || true
iptables -N FILTERS || true
iptables -A FILTERS -p tcp --dport 2222 -j ACCEPT  # SSH
iptables -A FILTERS -p tcp --dport 30303 -j ACCEPT # P2P tcp
iptables -A FILTERS -p udp --dport 30303 -j ACCEPT # P2P udp
iptables -A FILTERS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FILTERS -j DROP

# hook filters chain to input and docker
iptables -A INPUT -p icmp --icmp-type any -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -j FILTERS
iptables -P INPUT DROP

iptables -A DOCKER-USER -i $NETIF -j FILTERS
iptables -A DOCKER-USER -j RETURN
iptables-save > /etc/iptables/rules.v4

# run automated post-install audit
cd /opt/
wget https://downloads.cisofy.com/lynis/lynis-2.7.1.tar.gz
tar xvzf lynis-2.7.1.tar.gz
mv lynis /usr/local/
ln -s /usr/local/lynis/lynis /usr/bin/lynis
lynis audit system 


# Print install summary
cd $HOMEDIR
echo "==== EWF Affiliate Node Install Summary ====" > install-summary.txt
echo "Company: $COMPANY_NAME" >> install-summary.txt
echo "Validator Address: $ADDR" >> install-summary.txt
echo "Enode: $ENODE" >> install-summary.txt
echo "IP Address: $EXTERNAL_IP" >> install-summary.txt
echo "InfluxDB Username: $INFLUX_USER" >> install-summary.txt
echo "InfluxDB Password: $INFLUX_PASS" >> install-summary.txt
cat install-summary.txt


# END OF MAIN
}

## Files that get created

writeDockerCompose() {
cat > docker-compose.yml << 'EOF'
version: '3.5'
services:
  nethermind:
    image: ${NETHERMIND_VERSION}
    restart: always
    command:
      --config ${CHAINNAME}
    volumes:
      - ./configs:/nethermind/configs:ro
      - ./database:/nethermind/nethermind_db
      - ./keystore:/nethermind/keystore
      - ./logs:/nethermind/logs
      - ./NLog.config:/nethermind/NLog.config
    ports:
      - 30303:30303
      - 30303:30303/udp
      - 8545:8545

  nethermind-telemetry:
    image: nethermindeth/nethermind-telemetry:${NETHERMINDTELEMETRY_VERSION}
    restart: always
    environment:
      - WSURL=ws://nethermind:8545/ws/json-rpc
      - HTTPURL=http://nethermind:8545
      - PIPENAME=/var/spool/nethermind.sock
    volumes:
      - /var/spool/nethermind.sock:/var/spool/nethermind.sock
EOF

cat > .env << EOF
VALIDATOR_ADDRESS=$ADDR
EXTERNAL_IP=$EXTERNAL_IP
NETHERMIND_VERSION=$NETHERMIND_VERSION
NETHERMINDTELEMETRY_VERSION=$NETHERMINDTELEMETRY_VERSION
IS_SIGNING=true
NETHERMIND_KEY_FILE=./keystore/${NETHERMIND_KEY_FILE}
CHAINSPEC_CHKSUM=$CHAINSPEC_CHKSUM
CHAINSPEC_URL=$CHAINSPEC_URL
NETHERMIND_CHKSUM=$NETHERMIND_CHKSUM
CHAINNAME=$CHAINNAME
EOF

chmod 640 .env
chmod 640 docker-compose.yml
}

writeSShConfig() {
cat > /etc/ssh/sshd_config << EOF
Port 2222
PermitRootLogin no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
TCPKeepAlive no
MaxAuthTries 2

ClientAliveCountMax 2
Compression no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem	sftp	/usr/lib/openssh/sftp-server
EOF
}

function writeTelegrafConfig() {
cat > /etc/telegraf/telegraf.conf << EOF
[global_tags]
  affiliate = "$COMPANY_NAME"
  nodetype = "validator"
  validator = "$ADDR"
  enode = "$ENODE"
[agent]
  interval = "15s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "30s"
  flush_jitter = "5s"
  precision = ""
  debug = false
  quiet = true
  logfile = ""
  hostname = "$HOSTNAME"
  omit_hostname = false
[[outputs.influxdb]]
  urls = ["https://$CHAINNAME-influx-ingress.energyweb.org/"]
  database = "telemetry_$CHAINNAME"
  skip_database_creation = true
  username = "$INFLUX_USER"
  password = "$INFLUX_PASS"
[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false
  report_active = false
[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "devfs"]
[[inputs.diskio]]
[[inputs.kernel]]
[[inputs.mem]]
[[inputs.swap]]
[[inputs.system]]
[[inputs.docker]]
    tag_env = []
    endpoint = "unix:///var/run/docker.sock"
[[inputs.net]]
[[inputs.tail]]
   files = ["/var/spool/nethermind.sock"]
   pipe = true
   data_format = "json"

   tag_keys = []
   json_time_key = "timekey"
   json_time_format = "unix_ms"
   json_string_fields = ["client","blockHash"]
   name_override = "nethermind"
EOF
}

function writeDockerConfig() {
  cat > /etc/docker/daemon.json << EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
}

function writeNethermindConfig() {
cat > configs/volta.cfg << EOF
{
  "Init": {      
    "WebSocketsEnabled": true,
    "StoreReceipts" : true,
    "IsMining": true,
    "ChainSpecPath": "chainspec/volta.json",
    "GenesisHash": "0xebd8b413ca7b7f84a8dd20d17519ce2b01954c74d94a0a739a3e416abe0e43e5",
    "BaseDbPath": "nethermind_db/volta",
    "LogFileName": "volta.logs.txt",
    "MemoryHint": 256000000
  },
  "Network": {
    "DiscoveryPort": 30303,
    "P2PPort": 30303,
    "ActivePeersMaxCount": 25
  },
  "TxPool": {
      "Size": 512
  },
  "JsonRpc": {
    "Enabled": true,
    "TracerTimeout": 20000,
    "Host": "0.0.0.0",
    "Port": 8545    
  },
  "Db": {
    "CacheIndexAndFilterBlocks": false
  },
  "Sync": {
    "FastSync": true,
    "PivotNumber": 7690000,
    "PivotHash": "0x24a8bd7d60ce65b140489e9f74685a94dabcbd1796172f30e3547111ddefd1cf",
    "PivotTotalDifficulty": "2616771401622016784033350731150297545769543233",
    "FastBlocks" : true,
    "UseGethLimitsInFastBlocks" : false,
    "FastSyncCatchUpHeightDelta": 10000000000
  },
  "EthStats": {
    "Enabled": false,
    "Server": "ws://localhost:3000/api",
    "Name": "$COMPANY_NAME",
    "Secret": "secret",
    "Contact": "hello@nethermind.io"
  },
  "KeyStore": {
    "PasswordFiles": ["keystore/.secret"],
    "UnlockAccounts": ["$ADDR"],
    "BlockAuthorAccount": "$ADDR"
  },
  "Metrics": {
    "NodeName": "$COMPANY_NAME",
    "Enabled": false,
    "PushGatewayUrl": "http://localhost:9091/metrics",
    "IntervalSeconds": 5
  },
  "Seq": {
    "MinLevel": "Off",
    "ServerUrl": "http://localhost:5341",
    "ApiKey": ""
  },
  "Mining": {
    "TargetBlockGasLimit": $BLOCK_GAS
  },
  "Aura": {
    "ForceSealing": true
  }
}
EOF
chmod 644 configs/volta.cfg
}

function setJsonRpcLogsLevelToError() {
  sed -i '59s/.*/        <logger name="JsonRpc.*" minlevel="Error" writeTo="file-async"\/>/' NLog.config
  sed -i '60s/.*/        <logger name="JsonRpc.*" minlevel="Error" writeTo="auto-colored-console-async"\/>/' NLog.config
  sed -i '61s/.*/        <logger name="JsonRpc.*" final="true"\/>/' NLog.config
}

main