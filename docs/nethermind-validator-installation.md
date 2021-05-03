# Nethermind validator

## Shared secrets

The following files contain secrets that are used on the validators:

-   `keystore/.secret` => Contains the password for the ethereum private key
    Is accessed by `Nethermind` client to send transactions to the chain

The following values are considered as public keys in `.env`:

-   `VALIDATOR_ADDRESS` => Ethereum address of the validator account.

## Files created by the installation scripts

```
├── docker-stack
│   ├── .env [Configurations used by docker-compose.yml]
│   ├── chainspec [Stores network chainspec file]
│   │   └── volta.json
│   ├── configs [Stores Nethermind node configuration file]
│   │   └── volta.cfg
│   ├── database [Nethermind data directory]
│   │   └── volta
│   │       ├── blockInfos
│   │       ├── blocks
│   │       ├── bloom
│   │       ├── canonicalHashTrie
│   │       ├── code
│   │       ├── discoveryNodes
│   │       ├── headers
│   │       ├── peers
│   │       ├── pendingtxs
│   │       ├── receipts
│   │       └── state
│   ├── docker-compose.yml [Describes docker compose stack]
│   ├── keystore [Stores node/validator signing private keys]
│   │   ├── node.key.plain
│   │   ├── UTC--2020-08-17T07-30-18.187652000Z--6813ed3522372eef6200f3b1dbc3f819671cba69
│   │   ├── UTC--2020-08-17T07-30-22.975953000Z--494b1fa8f98c567af27f9321bacf0d3cdda9e7c8
│   │   └── UTC--2020-08-17T07-30-37.665937000Z--afcefdbe8362e93645864777317cef0abc3b57c2
│   ├── logs [Stores logs emitted by Nethermind client]
│   │   └── volta.logs.txt 
│   ├── NLog.config [NLog configuration file used for configuring which logs should be displayed and how]
├── install-validator.sh [Script to install a validator - can be removed after bootstrap]
├── install-summary.txt [Post installation summary file]
```

Other files:

 - `/etc/telegraf/telegraf.conf` -> Telegraf collection settings