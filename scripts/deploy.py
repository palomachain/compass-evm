from brownie import accounts, Turnstone
from eth_abi import encode_abi

def main():
    acct = accounts.load("deployer_account")
    validators = []
    powers = []
    valset_id = 0
    turnstone_id = b"ETH_01"
    Turnstone.deploy(encode_abi(["bytes32"], [turnstone_id]), [validators, powers, valset_id],{"from": acct})