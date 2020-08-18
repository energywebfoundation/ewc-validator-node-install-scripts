#!/bin/bash

set -e
set -o errexit
DEBIAN_FRONTEND=noninteractive

#CONFIG="volta.cfg"
SEQ_INSTANCE="https://seq.nethermind.io"
SEQ_MINLEVEL="Info"

whiptail --backtitle="Monitoring Settings" --title "Warning" --yes-button "Continue" --no-button "Abort" --yesno "This script will restart your node & telemetry" 8 60

CONFIG=$(whiptail --backtitle="Monitoring Settings" --title "Chains" --radiolist \
"Choose configuration that will be updated (to select use spacebar)" 20 60 4 \
"energyweb" "Energy Web Chain (production)" on \
"volta" "Volta Chain (dev)" off \
3>&1 1>&2 2>&3)

echo "Chain selected: " $CONFIG

CONFIG=$CONFIG.cfg

#check if docker-compose file exists
if test -f docker-compose.yml ; then
    echo "docker-compose.yml found, continue..."
else
    echo "this script must be executed in docker-stack directory"
    exit
fi
docker-compose down

cd configs/

# Grafana settings
until [[ -n "$PUSHGATEWAY_URL" ]]; do
	PUSHGATEWAY_URL=$(whiptail --backtitle="Monitoring Settings" --inputbox "Enter URL to the Pushgateway instance provided by Nethermind Team" 8 78 $PUSHGATEWAY_URL --title "Metrics Configuration" 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [[ $exitstatus = 0 ]]; then
                echo "PushGateway URL has been set to:" $PUSHGATEWAY_URL
        else
                break;
        fi
done

cat $CONFIG | jq '(.Metrics.Enabled) = true | (.Metrics.PushGatewayUrl) = "'$PUSHGATEWAY_URL'"' | sponge $CONFIG

# Seq settings
until [[ -n "$SEQ_APIKEY" ]]; do
	SEQ_APIKEY=$(whiptail --backtitle="Monitoring Settings" --inputbox "Enter Seq ApiKey provided by Nethermind Team" 8 78 $SEQ_APIKEY --title "Metrics Configuration" 3>&1 1>&2 2>&3)
        exitstatus=$?
        if [[ $exitstatus = 0 ]]; then
                echo "Seq ApiKey has been set to:" $SEQ_APIKEY
        else
                break;
        fi
done

cat $CONFIG | jq '(.Seq.MinLevel) = "'$SEQ_MINLEVEL'" | (.Seq.ServerUrl) = "'$SEQ_INSTANCE'" | (.Seq.ApiKey) = "'$SEQ_APIKEY'"' | sponge $CONFIG

echo "$CONFIG has been saved."
cd ..
docker-compose up -d