#!/usr/bin/python3

import pytest, brownie

from conftest import *

def test_submit_logic_call(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    transfer_amount = 5 * 10 ** 17
    func_sig = function_signature("transfer(address,uint256)")
    enc_abi = encode_abi(["address", "uint256"], [accounts[1].address, transfer_amount])
    payload = func_sig + enc_abi
    message_id = 1000
    valset_id = TurnstoneContract.last_valset_id()
    func_sig = function_signature("logic_call((address,bytes),uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)", "uint256", "uint256"], [[TestERC20Contract.address, payload], message_id, 2 ** 256 - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    TurnstoneContract.submit_logic_call(
        [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, valset_id], sigs], [TestERC20Contract, payload], message_id, 2 ** 256 - 1,
        {"from": accounts[0]}
    )
    assert TestERC20Contract.balanceOf(accounts[1]) == transfer_amount
