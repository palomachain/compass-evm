#!/usr/bin/python3

import pytest
from brownie import accounts, Compass, TestERC20, web3
from eth_abi import encode_abi
from eth_account import Account
from eth_account.messages import encode_defunct

@pytest.fixture
def CompassContract(validators, powers):
    return Compass.deploy(bstring2bytes32(b"ETH_01"), 0, [validators, powers, 0], {"from": accounts[0]})

@pytest.fixture
def TestERC20Contract():
    return TestERC20.deploy("TestERC20", "T20", 10 ** 18, {"from": accounts[0]})

@pytest.fixture(scope="session")
def validators():
    validator_list = []
    for i in range(4):
        accounts.add()
        validator_list.append(accounts[-1])
        print(accounts[-1])
    return validator_list

@pytest.fixture(scope="session")
def powers():
    return [2 ** 30, 2 ** 30, 2 ** 30, 2 ** 30]

def sign_hash(signers, hash):
    ret = []
    for signer in signers:
        signed_message = Account.sign_message(encode_defunct(hash), signer.private_key)
        ret.append([signed_message.v, signed_message.r, signed_message.s])
    return ret

def bstring2bytes32(str):
    return encode_abi(["bytes32"], [str])

def function_signature(str):
    return web3.keccak(text=str)[:4]