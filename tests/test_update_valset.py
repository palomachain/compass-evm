#!/usr/bin/python3

import pytest, brownie

from conftest import *

def test_update_valset_success(CompassContract, validators, powers, accounts):
    func_sig = function_signature("checkpoint(address[],uint256[],uint256,bytes32)")
    new_valset_id = 1
    enc_abi = encode_abi(["address[]","uint256[]","uint256","bytes32"], [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id, bstring2bytes32(b"ETH_01")])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    CompassContract.update_valset(
        [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 0], sigs],
        [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id],
        {"from": accounts[0]}
    )
    assert CompassContract.last_checkpoint() == hash.hex()

def test_update_valset_invalid_valset_id_revert(CompassContract, validators, powers, accounts):
    func_sig = function_signature("checkpoint(address[],uint256[],uint256,bytes32)")
    new_valset_id = 0
    enc_abi = encode_abi(["address[]","uint256[]","uint256","bytes32"], [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id, bstring2bytes32(b"ETH_01")])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    with brownie.reverts("Invalid Valset ID"):
        CompassContract.update_valset(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 0], sigs],
            [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id],
            {"from": accounts[0]}
        )

def test_update_valset_invalid_signature_revert(CompassContract, validators, powers, accounts):
    func_sig = function_signature("checkpoint(address[],uint256[],uint256,bytes32)")
    new_valset_id = 1
    enc_abi = encode_abi(["address[]","uint256[]","uint256","bytes32"], [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id, bstring2bytes32(b"ETH_01")])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    sigs[0][0] = 1
    with brownie.reverts("Invalid Signature"):
        CompassContract.update_valset(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 0], sigs],
            [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id + 1],
            {"from": accounts[0]}
        )

def test_update_valset_incorrect_checkpoint_revert(CompassContract, validators, powers, accounts):
    func_sig = function_signature("checkpoint(address[],uint256[],uint256,bytes32)")
    new_valset_id = 1
    enc_abi = encode_abi(["address[]","uint256[]","uint256","bytes32"], [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id, bstring2bytes32(b"ETH_01")])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    powers[0] += 1
    with brownie.reverts("Incorrect Checkpoint"):
        CompassContract.update_valset(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 0], sigs],
            [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id],
            {"from": accounts[0]}
        )

def test_update_valset_insufficient_power_revert(CompassContract, validators, powers, accounts):
    func_sig = function_signature("checkpoint(address[],uint256[],uint256,bytes32)")
    new_valset_id = 1
    enc_abi = encode_abi(["address[]","uint256[]","uint256","bytes32"], [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id, bstring2bytes32(b"ETH_01")])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    sigs[0][0] = 0
    sigs[1][0] = 0
    with brownie.reverts("Insufficient Power"):
        CompassContract.update_valset(
            [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 0], sigs],
            [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id],
            {"from": accounts[0]}
        )