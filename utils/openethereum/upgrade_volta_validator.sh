#!/bin/bash

#check if docker-compose file exists
if test -f docker-compose.yml ; then
    echo "docker-compose.yml found, continue..."
else
    echo "this script must be executed in docker-stack directory"
    exit
fi

 
#check if the script is already executed
if test -p /var/spool/parity.sock ; then
    exit
fi

#remove old output fifo
sed -i '/\[\[outputs\.file/,+2d' /etc/telegraf/telegraf.conf

#remove signer container
sed -i '/signer\:/,$d' docker-compose.yml

#create new fifo and fix owner
mkfifo /var/spool/parity.sock
chown telegraf /var/spool/parity.sock


#create nc-lastblock.txt to new node control version
touch config/nc-lastblock.txt


#get the telemetry user and pass
PASS=$(grep SFTP_PASS .env | cut -d'=' -f2)
USERNAME=$(grep VALIDATOR_ADDRESS .env  | cut -d'=' -f2)

#set the chain name
CHAINNAME="volta"

#get the keyfile
PARITY_KEY_FILE="$(ls -1 ./chain-data/keys/Volta/|grep UTC|head -n1)"

#append new configuration to telegraf
cat <<EOF >> /etc/telegraf/telegraf.conf
[[inputs.tail]]
   files = ["/var/spool/parity.sock"]
   pipe = true
   data_format = "json"

   tag_keys = []
   json_time_key = "timekey"
   json_time_format = "unix_ms"
   json_string_fields = ["client","blockHash"]
   name_override = "parity"
[[outputs.influxdb]]
  urls = ["https://$CHAINNAME-influx-ingress.energyweb.org/"]
  database = "telemetry_$CHAINNAME"
  skip_database_creation = true
  username = "$USERNAME"
  password = "$PASS"

EOF

#append parity-telemetry to docker-compose
cat <<'EOF' >> docker-compose.yml
  nodecontrol:
    image: energyweb/nodecontrol:${NODECONTROL_VERSION}
    restart: always
    volumes:
      - $PWD:$PWD
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config/nc-lastblock.txt:/lastblock.txt
      - $PARITY_KEY_FILE:/paritykey:ro
    environment:
      - CONTRACT_ADDRESS=0x1204700000000000000000000000000000000007
      - STACK_PATH=$PWD
      - RPC_ENDPOINT=http://parity:8545
      - VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS}
      - BLOCKFILE_PATH=/lastblock.txt
      - KEYFILE_PATH=/paritykey

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

#apend parity-telemetry version to env
echo 'PARITYTELEMETRY_VERSION=1.1.0' >> .env

#upgrade the node_control version
sed -i 's/NODECONTROL_VERSION=v0.9.18/NODECONTROL_VERSION=v1.0.0/' .env

echo "PARITY_KEY_FILE=./chain-data/keys/Volta/${PARITY_KEY_FILE}" >> .env

service telegraf restart
docker-compose up --remove-orphans -d

