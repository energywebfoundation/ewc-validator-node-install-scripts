# EWC validator node install scripts

EWC and Volta affiliate validator node installation scripts.

**Keep a scratch file ready to collect outputs in - You'll need them**

### Steps 

See our Atlassian wiki for[installation instructions](https://energyweb.atlassian.net/wiki/spaces/EWF/pages/718536737/Setting+Up+a+New+Validator+Node)

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

