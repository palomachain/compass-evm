import json
import subprocess
import sys

from brownie import Turnstone, accounts
from eth_abi import encode_abi


def get_valset(node, valset_id=None):
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
    # print(stdout)
    # stdout = str(stdout)
    # stderr = str(stderr)

    # print(stdout)

    valset = json.loads(stdout)
    valset = valset["valset"]
    print(valset)
    # validators are strings returned like this: "0xabcd...."
    return valset["validators"], valset["powers"], valset["valsetID"]


def main():
    # node = sys.argv[1]
    # assert node, "must provide 1 argument which is the node: e.g. tcp://localhost:26657"
    node = "tcp://localhost:26657"
    validators, powers, valset_id = get_valset(node)

    # power_sum = sum(powers)

    # assert power_sum >= 2863311530, f"not enough power to reach consensus: {power_sum}"

    acct = accounts[0]
    turnstone_id = b""  # should update
    Turnstone.deploy(
        encode_abi(["bytes32"], [turnstone_id]),
        [validators, powers, valset_id],
        {"from": acct},
    )


if __name__ == "__main__":
    main()
