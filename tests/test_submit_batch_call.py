#!/usr/bin/python3

import pytest, brownie

from conftest import *

def test_submit_batch_call(TurnstoneContract, TestERC20Contract, validators, powers, accounts):
    TestERC20Contract.transfer(TurnstoneContract, 10 ** 18, {"from": accounts[0]})
    func_sig = function_signature("transfer(address,uint256)")
    args = []
    enc_abi = encode_abi(["address", "uint256"], [accounts[2].address, 10 ** 17])
    args.append([TestERC20Contract.address, func_sig + enc_abi])
    enc_abi = encode_abi(["address", "uint256"], [accounts[3].address, 2 * 10 ** 17])
    args.append([TestERC20Contract.address, func_sig + enc_abi])

    func_sig = function_signature("batch_logic_call((address,bytes)[],uint256,uint256)")
    enc_abi = encode_abi(["(address,bytes)[]", "uint256", "uint256"], [args, 0, 2 ** 256 - 1])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    TurnstoneContract.submit_batch_call(
        [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 0], sigs], args, 0, 2 ** 256 - 1,
        {"from": accounts[0]}
    )
    assert TestERC20Contract.balanceOf(accounts[2]) == 10 ** 17
    assert TestERC20Contract.balanceOf(accounts[3]) == 2 * 10 ** 17