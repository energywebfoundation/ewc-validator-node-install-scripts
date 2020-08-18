#!/bin/bash
# updates Nethermind Ethereum on EWF validator nodes

display_usage() { 
	echo "EWF Nethermind update utility"
	echo "This script must be run with super-user privileges." 
	echo -e "\nUsage:\n./updateNethermind.sh [user name] [docker name] [docker id]\nExample:\n./updateNethermind.sh ubuntu nethermind/nethermind:1.8.80 sha256:fb4b2c1fd1a76f653f1622a577dbad05f859584fbc188c5d470d8c925e5de2cc"
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
		NETHERMIND_VERSION=$2
		NETHERMIND_CHKSUM=$3
		# update the .env file
		sed -i "s|NETHERMIND_VERSION=.*|NETHERMIND_VERSION=$NETHERMIND_VERSION|g" .env
		sed -i "s|NETHERMIND_CHKSUM=.*|NETHERMIND_CHKSUM=$NETHERMIND_CHKSUM|g" .env
		docker pull $NETHERMIND_VERSION
		# verify image
		IMGHASH="$(docker image inspect $NETHERMIND_VERSION|jq -r '.[0].Id')"
		if [ "$NETHERMIND_CHKSUM" != "$IMGHASH" ]; then
  			echo "ERROR: Unable to verify Nethermind docker image. Checksum missmatch."
  			exit 1;
		fi
		docker-compose restart
		echo "Updated Nethermind to $NETHERMIND_VERSION"
	else
		echo "Wrong folder: cd /home/admin/docker-stack if your login user is admin"
		exit 1
	fi
else
	echo "Nothing done: 3 argument required, $# provided"
	exit 1
fi
