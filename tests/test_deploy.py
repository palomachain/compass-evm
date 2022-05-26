#!/usr/bin/python3

import pytest, brownie

from conftest import *

def test_deploy(TurnstoneContract): 
    assert TurnstoneContract.turnstone_id().decode("utf8") == "ETH_01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
