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


#get the telemetry user and pass
PASS=$(grep SFTP_PASS .env | cut -d'=' -f2)
USERNAME=$(grep EXTERNAL_IP .env  | cut -d'=' -f2)

#set the chain name
CHAINNAME="volta"

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
  username = "proxy-$USERNAME"
  password = "$PASS"

EOF

#append parity-telemetry to docker-compose
cat <<'EOF' >> docker-compose.yml
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

service telegraf restart
docker-compose up --remove-orphans -d

