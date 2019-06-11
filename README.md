# EWC validator node install scripts

EWC and Volta affiliate validator node installation scripts.

**Keep a scratch file ready to collect outputs in - You'll need them**

### Steps 

1. Prepare an host according to the [system architecture paper](https://github.com/energywebfoundation/system-design-spec-live) (minimal install with ssh) with one of the following operating systems:
    - Debian v9.x
    - Ubuntu 18.04 LTS
    - CentOS 7
2. Copy the script matching the installed OS from the `affiliate` directory to the host
3. SSH into the new host
4. Make sure the latest system updates are installed by running `apt-get update && apt-get dist-upgrade` (debian/ubuntu) or `yum update` (centos)
5. Make the scrip executable with `chmod +x ./install-*.sh`
6. Run the script (user parameter `--auto` takes default values for node-name and generates a random key which is NOT recommended for production use)
7. Send the installation summary to EWF netops to [netops@energyweb.org](netops@energyweb.org)

## Shared secrets

The following files contain secrets that are used on the validators:

-   `.secret` => Contains the password for the ethereum private key
    Is accessed by `parity` and `nodecontrol` to send transactions to the chain
-   `.env` => Contains the individual second channel password in the `SFTP_PASS` variable. Used by `nodecontrol`
-   files in `signer-data/` used by the signer to store the signers encrypted private RSA key for signing telemetry packets.

The following values are considered as public keys in `.env`:

-   `VALIDATOR_ADDRESS` => Ethereum address of the validator account. Used by `signer` and `nodecontrol` for identification.
-   `TELEMETRY_INGRESS_FINGERPRINT` => SHA256 fingerprint of the Ingress TLS certificate. Ingress presented cert needs to verify against the fingerprint.
-   `SFTP_FINGER_PRINT` => Fingerprint of the SSH hostkey when connecting to the second channel.

## Files created by the installation scripts

```
├── docker-stack
│   ├── .env [Configurations used by docker-compose.yml]
│   ├── chain-data [Parity data directory]
│   │   ├── cache
│   │   ├── chains
│   │   │   ├── ver.lock
│   │   │   └── Volta [Blockchainb DB]
│   │   │       .
│   │   ├── keys
│   │   │   └── Volta
│   │   │       ├── address_book.json
│   │   │       └── UTC--2019-04-03T10-11-45Z--4d496ffe-8b48-e2a1-881f-351f03ae5539 [Validator signing key (not on bootnode)]
│   │   ├── network
│   │   │   └── key
│   │   └── signer
│   ├── config
│   │   ├── chainspec.json 
│   │   ├── parity-non-signing.toml [Parity configuration when signing disabled by nodecontrol]
│   │   ├── parity-signing.toml [Parity configuration when signing enabled by nodecontrol (default)]
│   │   └── peers
│   ├── curcron
│   ├── docker-compose.yml [Describes the compose stack]
│   └── signer-data
│       ├── signing.key [Encrypted RSA private key of the signer]
│       └── signing.salt [Salt used to decrypt the RSA key on signer start]
└── install-validator.sh [Script to install a validator - can be removed after bootstrap]
```

Other files:

 - `/var/run/influxdb.sock` -> Named pipe for telegraf to write telemetry to and signer to read from.
 - `/etc/telegraf/telegraf.conf` -> Telegraf collection settings

