#!/usr/bin/python3

import pytest, brownie

from conftest import *

def test_update_valset(TurnstoneContract, validators, powers, accounts):
    func_sig = function_signature("checkpoint(address[],uint256[],uint256,bytes32)")
    enc_abi = encode_abi(["address[]","uint256[]","uint256","bytes32"], [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 1, bstring2bytes32(b"ETH_01")])
    hash = web3.keccak(func_sig + enc_abi)
    sigs = sign_hash(validators, hash)
    new_valset_id = 1
    TurnstoneContract.update_valset(
        [[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, new_valset_id],
        [[[validators[0].address, validators[1].address, validators[2].address, validators[3].address], powers, 0], sigs],
        {"from": accounts[0]}
    )
    assert TurnstoneContract.last_checkpoint() == hash.hex()
