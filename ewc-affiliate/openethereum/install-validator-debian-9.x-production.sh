#!/bin/bash

# Make the script exit on any error
set -e
set -o errexit
export DEBIAN_FRONTEND=noninteractive

# Configuration Block - Docker checksums are the image Id
PARITY_VERSION="openethereum/openethereum:v3.3.3"
PARITY_CHKSUM="sha256:8020068920b97070f9d5c276c96a5b042035bbf40c88ee5c841e71e8bba03e01"

PARITYTELEMETRY_VERSION="1.1.0"
PARITYTELEMETRY_CHKSUM="sha256:00e3a14c5e9c6629eedfcece86e12599f5813c0f2fc075689efa1233aa0cfef7"

TELEGRAF_VERSION="1.9.4"
TELEGRAF_CHKSUM="5e52c05988c17d652dbbdfc7a501be69490b6c935b66ccc1ea0aceaca7b48159  telegraf_1.9.4-1_amd64.deb"

# Chain/Parity configuration
BLOCK_GAS="8000000"
CHAINNAME="EnergyWebChain"
CHAINSPEC_URL="https://raw.githubusercontent.com/energywebfoundation/ewf-chainspec/master/EnergyWebChain.json"
KEY_SEED="0x$(openssl rand -hex 32)"

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
CHAINNAMELOWER="$(echo $CHAINNAME | awk '{print tolower($0)}')"
# Install system updates and required tools and dependencies
echo "Installing dependencies"

# Preparing iptables auto-save
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections

apt-get install -y curl net-tools dnsutils expect jq iptables-persistent debsums chkrootkit

# Collecting information from the user

# Get external IP from OpenDNS
EXTERNAL_IP="$(dig @resolver1.opendns.com ANY myip.opendns.com +short)"
COMPANY_NAME="validator-$EXTERNAL_IP"

if [ ! "$1" == "--auto" ];
then
# Show a warning that SSH login is restriced after install finishes
whiptail --backtitle="EWF Genesis Node Installer" --title "Warning" --yes-button "Continue" --no-button "Abort" --yesno "After the installation is finished you can only login through SSH with the current user on port 2222 and the key provided in the next steps." 10 60
HOMEDIR=$(pwd)
# Confirm user home directory
whiptail --backtitle="EWF Genesis Node Installer" --title "Confirm Home Directory" --yesno "Is $(pwd) the normal users home directory?" 8 60

COMPANY_NAME=$(whiptail --backtitle="EWF Genesis Node Installer" --inputbox "Enter Affiliate/Company Name (will be cut to 30 chars)" 8 78 "$COMPANY_NAME" --title "Node Configuration" 3>&1 1>&2 2>&3)
KEY_SEED=$(whiptail --backtitle="EWF Genesis Node Installer" --inputbox "Enter Validator account seed (32byte hex with 0x)" 8 78 "$KEY_SEED" --title "Node Configuration" 3>&1 1>&2 2>&3)
EXTERNAL_IP=$(whiptail --backtitle="EWF Genesis Node Installer" --inputbox "Enter this hosts public IP" 8 78 "$EXTERNAL_IP" --title "Connectivity" 3>&1 1>&2 2>&3)
NETIF=$(whiptail --backtitle="EWF Genesis Node Installer" --inputbox "Enter this hosts primary network interface" 8 78 "$NETIF" --title "Connectivity" 3>&1 1>&2 2>&3)
fi

COMPANY_NAME=$(echo "$COMPANY_NAME" | cut -c -30)

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
curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
chmod +x /usr/bin/docker-compose

# Install the Telegrad telemetry collector
echo "Install Telegraf..."
wget https://dl.influxdata.com/telegraf/releases/telegraf_$TELEGRAF_VERSION-1_amd64.deb

# Verify
TG_CHK="$(sha256sum telegraf_$TELEGRAF_VERSION-1_amd64.deb)"
if [ "$TELEGRAF_CHKSUM" != "$TG_CHK" ]; then
  echo "ERROR: Unable to verify telegraf package. Checksum missmatch."
  exit 1;
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
docker pull $PARITY_VERSION

# verify image
IMGHASH="$(docker image inspect $PARITY_VERSION|jq -r '.[0].Id')"
if [ "$PARITY_CHKSUM" != "$IMGHASH" ]; then
  echo "ERROR: Unable to verify parity docker image. Checksum missmatch."
  exit 1;
fi

docker pull energyweb/parity-telemetry:$PARITYTELEMETRY_VERSION
IMGHASH="$(docker image inspect energyweb/parity-telemetry:$PARITYTELEMETRY_VERSION|jq -r '.[0].Id')"
if [ "$PARITYTELEMETRY_CHKSUM" != "$IMGHASH" ]; then
  echo "ERROR: Unable to verify parity-telemetry docker image. Checksum missmatch."
  exit 1;
fi
# Create the directory structure
mkdir docker-stack
chmod 750 docker-stack
cd docker-stack
mkdir config
mkdir chain-data

touch config/peers

chown 1000:1000 chain-data
chmod 777 chain-data

# Prepare the parity client
# Creates 2 config one with siging enabled and one without
writeParityConfig

cp config/parity-non-signing.toml config/parity-signing.toml

echo "Fetch Chainspec..."
# TODO: replace with chainspec location
wget $CHAINSPEC_URL -O config/chainspec.json

echo "Creating Account..."

# Generate random account password and store
XPATH="$(pwd)"
PASSWORD="$(openssl rand -hex 32)"
echo "$PASSWORD" > .secret
chmod 400 .secret
chown 1000:1000 .secret

# Launch oneshot docker
docker run -d --name parity-keygen \
    -p 127.0.0.1:8545:8545 \
    -v "${XPATH}"/chain-data/:/home/openethereum/.local/share/io.parity.ethereum/ \
    -v "${XPATH}"/config:/parity/config:ro ${PARITY_VERSION} \
    --config /parity/config/parity-non-signing.toml --jsonrpc-apis=parity_accounts

# Wait for parity to sort itself out
sleep 20

generate_account_data()
{
cat << EOF
{ "method": "parity_newAccountFromSecret", "params": ["$KEY_SEED","$PASSWORD"], "id": 1, "jsonrpc": "2.0" }
EOF
}
# Send request to create account from seed
ADDR=$(curl -s --request POST --url http://localhost:8545/ --header 'content-type: application/json' --data "$(generate_account_data)" | jq -r '.result')

echo "Account created: $ADDR"
INFLUX_USER="$(echo $ADDR | cut -c -20)"
INFLUX_PASS="$(openssl rand -hex 16)"

# got the key now discard of the parity instance
docker stop parity-keygen
docker rm -f parity-keygen

PARITY_KEY_FILE="$(ls -1 ./chain-data/keys/$CHAINNAME/|grep UTC|head -n1)"

cat >> config/parity-signing.toml << EOF
engine_signer = "$ADDR"

[account]
password = ["/parity/authority.pwd"]
keys_iterations = 10240
EOF
chmod 644 config/parity-signing.toml
# Prepare parity telemetry pipe
mkfifo /var/spool/parity.sock
chown telegraf /var/spool/parity.sock
# touch the blockfile to avoid docker creating a dir
touch config/nc-lastblock.txt
# Write the docker-compose file to disk
writeDockerCompose

# start everything up
docker-compose up -d

# Collect the enode from parity over RPC
echo "Waiting 30 sec for parity to come up and generate the enode..."
sleep 30
ENODE=$(curl -s --request POST --url http://localhost:8545/ --header 'content-type: application/json' --data '{ "method": "parity_enode", "params": [], "id": 1, "jsonrpc": "2.0" }' | jq -r '.result')

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

iptables -A DOCKER-USER -i "$NETIF" -j FILTERS
iptables -A DOCKER-USER -j RETURN
iptables-save > /etc/iptables/rules.v4

# run automated post-install audit
cd /opt/
wget https://downloads.cisofy.com/lynis/lynis-3.1.4.tar.gz
tar xvzf lynis-2.7.1.tar.gz
mv lynis /usr/local/
ln -s /usr/local/lynis/lynis /usr/local/bin/lynis
lynis audit system


# Print install summary
# Print install summary
cd "$HOMEDIR" || exit 1
{
  echo "==== EWF Affiliate Node Install Summary ===="
  echo "Company: ${COMPANY_NAME}"
  echo "Validator Address: ${ADDR}"
  echo "Enode: ${ENODE}"
  echo "IP Address: ${EXTERNAL_IP}"
  echo "InfluxDB Username: ${INFLUX_USER}"
  echo "InfluxDB Password: ${INFLUX_PASS}"
} > install-summary.txt
cat install-summary.txt

# END OF MAIN
}

## Files that get created


writeDockerCompose() {
cat > docker-compose.yml << 'EOF'
version: '2.0'
services:
  parity:
    image: ${PARITY_VERSION}
    restart: always
    command:
      --config /parity/config/parity-${IS_SIGNING}.toml
      --nat extip:${EXTERNAL_IP}
    volumes:
      - ./config:/parity/config:ro
      - ./chain-data:/home/openethereum/.local/share/io.parity.ethereum/
      - ./.secret:/parity/authority.pwd:ro
    ports:
      - 30303:30303
      - 30303:30303/udp
      - 127.0.0.1:8545:8545

  parity-telemetry:
    image: energyweb/parity-telemetry:${PARITYTELEMETRY_VERSION}
    restart: always
    environment:
      - WSURL=ws://parity:8546
      - HTTPURL=http://parity:8545
      - PIPENAME=/var/spool/parity.sock
    volumes:
      - /var/spool/parity.sock:/var/spool/parity.sock
EOF

cat > .env << EOF
VALIDATOR_ADDRESS=$ADDR
EXTERNAL_IP=$EXTERNAL_IP
PARITY_VERSION=$PARITY_VERSION
PARITYTELEMETRY_VERSION=$PARITYTELEMETRY_VERSION
IS_SIGNING=signing
PARITY_KEY_FILE=./chain-data/keys/${CHAINNAME}/${PARITY_KEY_FILE}
CHAINSPEC_CHKSUM=$CHAINSPEC_CHKSUM
CHAINSPEC_URL=https://example.com
PARITY_CHKSUM=$PARITY_CHKSUM
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

writeTelegrafConfig() {
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
  urls = ["https://$CHAINNAMELOWER-influx-ingress.energyweb.org/"]
  database = "telemetry_$CHAINNAMELOWER"
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
   files = ["/var/spool/parity.sock"]
   pipe = true
   data_format = "json"

   tag_keys = []
   json_time_key = "timekey"
   json_time_format = "unix_ms"
   json_string_fields = ["client","blockHash"]
   name_override = "parity"
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

function writeParityConfig() {
cat > config/parity-non-signing.toml << EOF
[parity]
chain = "/parity/config/chainspec.json"
no_persistent_txqueue = true

[rpc]
disable = false
port = 8545
interface = "0.0.0.0"
cors = []
apis = ["eth", "net", "parity", "web3"]

[websockets]
disable = false
interface = "0.0.0.0"
port = 8546

[ipc]
disable = true

[secretstore]
disable = true

[network]
port = 30303
min_peers = 25
max_peers = 50
discovery = true
warp = false
allow_ips = "all"
snapshot_peers = 0
max_pending_peers = 64

[footprint]
db_compaction = "ssd"

[snapshots]
enable = false

[mining]
force_sealing = true
usd_per_tx = "0.000000000000000001"
usd_per_eth = "1"
price_update_period = "hourly"
min_gas_price = 1
gas_cap = "$BLOCK_GAS"
gas_floor_target = "$BLOCK_GAS"
tx_gas_limit = "$BLOCK_GAS"
extra_data = "$COMPANY_NAME"
EOF
chmod 644 config/parity-non-signing.toml
}

main
