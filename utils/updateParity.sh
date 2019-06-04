#!/bin/bash
# updates Parity Ethereum on EWF validator nodes

display_usage() { 
	echo "EWF Parity update utility"
	echo "This script must be run with super-user privileges." 
	echo -e "\nUsage:\n./updateParity.sh [user name] [docker name] [docker id]\nExample:\n./updateParity ubuntu parity/parity:v2.4.6 sha256:952161b0410746ee6500b21e83a8cf422c24f1d86f031e3e7a48c5b501e70638"
} 

# display usage 
if [  $# -le 2 ] 
then 
	display_usage
	exit 1
fi 
 
if [[ ( $# == "--help") ||  $# == "-h" ]] 
then 
	display_usage
	exit 0
fi 
 
if [[ $USER != "root" ]]; then 
	echo "This script must be run as root! Type: sudo -s" 
	exit 1
fi

if [[ "$#" -eq 3 ]]; then
	if [ "$PWD" = /home/$1/docker-stack ]; then
		PARITY_VERSION=$2
		PARITY_CHKSUM=$3
		# update the .env file
		sed -i "s|PARITY_VERSION=.*|PARITY_VERSION=$PARITY_VERSION|g" .env
		sed -i "s|PARITY_CHKSUM=.*|PARITY_CHKSUM=$PARITY_CHKSUM|g" .env
		docker pull $PARITY_VERSION
		# verify image
		IMGHASH="$(docker image inspect $PARITY_VERSION|jq -r '.[0].Id')"
		if [ "$PARITY_CHKSUM" != "$IMGHASH" ]; then
  			echo "ERROR: Unable to verify parity docker image. Checksum missmatch."
  			exit 1;
		fi
		docker-compose up -d
		echo "Updated Parity to $PARITY_VERSION"
	else
		echo "Wrong folder: cd /home/admin/docker-stack if your login user is admin"
		exit 1
	fi
else
	echo "Nothing done: 3 argument required, $# provided"
	exit 1
fi
