FROM ubuntu:18.04
RUN apt update \
  && apt install -y wget python3 python3-dev python3-pip build-essential \
  && rm -rf /var/lib/apt/lists/* \
  && pip3 install web3 \
  && wget https://raw.githubusercontent.com/energywebfoundation/ewc-validator-node-install-scripts/dev/utils/change_payout_address.py
ENTRYPOINT ["python3", "change_payout_address.py"]
