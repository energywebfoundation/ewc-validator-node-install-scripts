from web3.auto import w3
import argparse
import os
import json

# defaults
REWARD_CONTRACT = '0x1204700000000000000000000000000000000003'
REWARD_ABI = '[ { "constant": false, "inputs": [], "name": "resetPayoutAddress", "outputs": [], "payable": false, "stateMutability": "nonpayable", "type": "function" }, { "constant": false, "inputs": [ { "name": "benefactors", "type": "address[]" }, { "name": "kind", "type": "uint16[]" } ], "name": "reward", "outputs": [ { "name": "", "type": "address[]" }, { "name": "", "type": "uint256[]" } ], "payable": false, "stateMutability": "nonpayable", "type": "function" }, { "constant": false, "inputs": [ { "name": "_newFund", "type": "address" } ], "name": "setCommunityFund", "outputs": [], "payable": false, "stateMutability": "nonpayable", "type": "function" }, { "constant": false, "inputs": [ { "name": "_newPayoutAddress", "type": "address" } ], "name": "setPayoutAddress", "outputs": [], "payable": false, "stateMutability": "nonpayable", "type": "function" }, { "inputs": [ { "name": "_communityFundAddress", "type": "address" }, { "name": "_communityFundAmount", "type": "uint256" } ], "payable": false, "stateMutability": "nonpayable", "type": "constructor" }, { "constant": true, "inputs": [], "name": "blockStepSize", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [], "name": "checkRewardPeriodEnded", "outputs": [ { "name": "", "type": "bool" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [], "name": "communityFund", "outputs": [ { "name": "", "type": "address" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [], "name": "communityFundAmount", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "_currentBlock", "type": "uint256" } ], "name": "getBlockReward", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "address" } ], "name": "mintedForAccount", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "address" }, { "name": "", "type": "uint256" } ], "name": "mintedForAccountInBlock", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [], "name": "mintedForCommunity", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "address" } ], "name": "mintedForCommunityForAccount", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "uint256" } ], "name": "mintedInBlock", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [], "name": "mintedTotally", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "address" } ], "name": "payoutAddresses", "outputs": [ { "name": "", "type": "address" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [], "name": "rewardPeriodEnd", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" }, { "constant": true, "inputs": [ { "name": "", "type": "uint256" } ], "name": "sCurve", "outputs": [ { "name": "", "type": "uint256" } ], "payable": false, "stateMutability": "view", "type": "function" } ]'
CHAIN_ID = 0x12047
SECRET = 'docker-stack/.secret'
KEYDIR = 'docker-stack/chain-data/keys/Volta/'

# parse arguments
parser = argparse.ArgumentParser()
parser.add_argument('--keydir', help="Directory where you store the key file", default=KEYDIR)
parser.add_argument('--secret', help="Path of the encryption key", default=SECRET)
parser.add_argument('--payoutAddress', help="Payout address", required=True)
parser.add_argument('--chain', help="Chain ID in hex format", default=CHAIN_ID)
args = parser.parse_args()

# init contract
reward_contract = w3.eth.contract(address=REWARD_CONTRACT, abi=REWARD_ABI)

# get secret
with open(args.secret, mode='r') as encryption_key:
    secret = encryption_key.readline().strip()

# unlock and sign
key_files = [f for f in os.listdir(args.keydir) if f.startswith('UTC')]
if len(key_files) > 1:
    raise Exception('Found more than one key')

pkey = args.keydir + key_files[0]
with open(pkey, mode='r') as keyfile:
    encrypted_key = keyfile.read()
    encrypted_key_info = json.loads(encrypted_key)
    private_key = w3.eth.account.decrypt(encrypted_key, secret)
    address = w3.toChecksumAddress(encrypted_key_info['address'])
    nonce = w3.eth.getTransactionCount(address)
    metadata = {'nonce': nonce,
                'gas': 100000,
                'gasPrice': 10,
                'value': 0,
                'chainId': args.chain
                }
    transaction = reward_contract.functions.setPayoutAddress(str(args.payoutAddress)).buildTransaction(metadata)
    signed_tx = w3.eth.account.signTransaction(transaction, private_key)
    tx_hash = w3.eth.sendRawTransaction(signed_tx.rawTransaction)
    w3.eth.waitForTransactionReceipt(tx_hash)
    print('Success. Tx hash: {}'.format(bytes(tx_hash).hex()))
