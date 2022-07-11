import json
import subprocess
import sys

from brownie import Turnstone, accounts
from eth_abi import encode_abi


def get_valset(node):
    process = subprocess.Popen(
        [
            "palomad",
            "--node",
            node,
            "--output",
            "json",
            "query",
            "evm",
            "get-valset-by-id",
            "0",
            "eth-main",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    stdout, stderr = process.communicate()

    valset = json.loads(stdout)
    valset = valset["valset"]
    # validators are strings returned like this: "0xabcd...."
    return valset["validators"], valset["powers"], valset["valsetID"]


def main():
    node = "tcp://localhost:26657"
    validators, powers, valset_id = get_valset(node)

    acct = accounts.load("deployer_account")
    turnstone_id = b""  # should update
    Turnstone.deploy(
        encode_abi(["bytes32"], [turnstone_id]),
        [validators, powers, valset_id],
        {"from": acct},
    )


if __name__ == "__main__":
    main()
