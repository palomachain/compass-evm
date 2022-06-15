from brownie import accounts, Turnstone
from eth_abi import encode_abi

def main():
    acct = accounts.load("deployer_account")
    validators = [] # should update
    powers = [] # should update
    valset_id = 0 # should update
    turnstone_id = b"ETH_01" # should update
    Turnstone.deploy(encode_abi(["bytes32"], [turnstone_id]), [validators, powers, valset_id],{"from": acct})