from brownie import accounts, Compass
from eth_abi import encode_abi

def main():
    acct = accounts.load("deployer_account")
    validators = [] # should update
    powers = [] # should update
    valset_id = 0 # should update
    compass_id = b"ETH_01" # should update
    Compass.deploy(encode_abi(["bytes32"], [compass_id]), [validators, powers, valset_id],{"from": acct})