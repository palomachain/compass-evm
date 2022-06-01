#!/usr/bin/python3

import pytest, brownie

from conftest import *
from brownie.network.state import Chain

def test_submit_logic_call_success(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    transfer_amount = 5 * 10 ** 17
    func_sig = function_signature("transfer(address,uint256)")
    enc_abi = encode_abi(["address", "uint256"], [accounts[1].address, transfer_amount])
    payload = func_sig + enc_abi
    message_id = 1000
    valset_id = 0
    func_sig = function_signature("logic_call((address,bytes),uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)", "uint256", "uint256"], [[TestERC20Contract.address, payload], message_id, 2 ** 256 - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    TurnstoneContract.submit_logic_call(
        [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, 2 ** 256 - 1,
        {"from": accounts[0]}
    )
    assert TestERC20Contract.balanceOf(accounts[1]) == transfer_amount

def test_submit_logic_call_timeout_revert(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    transfer_amount = 5 * 10 ** 17
    func_sig = function_signature("transfer(address,uint256)")
    enc_abi = encode_abi(["address", "uint256"], [accounts[1].address, transfer_amount])
    payload = func_sig + enc_abi
    message_id = 1000
    valset_id = 0
    chain = Chain()
    timestamp = chain.time()
    func_sig = function_signature("logic_call((address,bytes),uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)", "uint256", "uint256"], [[TestERC20Contract.address, payload], message_id, timestamp - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    with brownie.reverts("Timeout"):
        TurnstoneContract.submit_logic_call(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, timestamp - 1,
            {"from": accounts[0]}
        )

def test_submit_logic_call_used_message_id_revert(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    transfer_amount = 5 * 10 ** 17
    func_sig = function_signature("transfer(address,uint256)")
    enc_abi = encode_abi(["address", "uint256"], [accounts[1].address, transfer_amount])
    payload = func_sig + enc_abi
    message_id = 1000
    valset_id = 0
    func_sig = function_signature("logic_call((address,bytes),uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)", "uint256", "uint256"], [[TestERC20Contract.address, payload], message_id, 2 ** 256 - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    TurnstoneContract.submit_logic_call(
        [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, 2 ** 256 - 1,
        {"from": accounts[0]}
    )
    with brownie.reverts("Used Message_ID"):
        TurnstoneContract.submit_logic_call(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, 2 ** 256 - 1,
            {"from": accounts[0]}
        )

def test_submit_logic_call_incorrect_checkpoint_revert(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    transfer_amount = 5 * 10 ** 17
    func_sig = function_signature("transfer(address,uint256)")
    enc_abi = encode_abi(["address", "uint256"], [accounts[1].address, transfer_amount])
    payload = func_sig + enc_abi
    message_id = 1000
    valset_id = 0
    func_sig = function_signature("logic_call((address,bytes),uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)", "uint256", "uint256"], [[TestERC20Contract.address, payload], message_id, 2 ** 256 - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    powers[0] -= 1
    with brownie.reverts("Incorrect Checkpoint"):
        TurnstoneContract.submit_logic_call(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, 2 ** 256 - 1,
            {"from": accounts[0]}
        )

def test_submit_logic_call_invalid_signature(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    transfer_amount = 5 * 10 ** 17
    func_sig = function_signature("transfer(address,uint256)")
    enc_abi = encode_abi(["address", "uint256"], [accounts[1].address, transfer_amount])
    payload = func_sig + enc_abi
    message_id = 1000
    valset_id = 0
    func_sig = function_signature("logic_call((address,bytes),uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)", "uint256", "uint256"], [[TestERC20Contract.address, payload], message_id, 2 ** 256 - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    sigs[0][0] = 1
    with brownie.reverts("Invalid Signature"):
        TurnstoneContract.submit_logic_call(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, 2 ** 256 - 1,
            {"from": accounts[0]}
        )

def test_submit_logic_call_insufficient_power(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    transfer_amount = 5 * 10 ** 17
    func_sig = function_signature("transfer(address,uint256)")
    enc_abi = encode_abi(["address", "uint256"], [accounts[1].address, transfer_amount])
    payload = func_sig + enc_abi
    message_id = 1000
    valset_id = 0
    func_sig = function_signature("logic_call((address,bytes),uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)", "uint256", "uint256"], [[TestERC20Contract.address, payload], message_id, 2 ** 256 - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    sigs[0][0] = 0
    sigs[1][0] = 0
    with brownie.reverts("Insufficient Power"):
        TurnstoneContract.submit_logic_call(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, 2 ** 256 - 1,
            {"from": accounts[0]}
        )