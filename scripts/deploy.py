import json
import subprocess
import sys

from brownie import Turnstone, accounts
from eth_abi import encode_abi


def get_valset(node, valset_id=None):
    if valset_id is None:
        valset_id = 99999999
    print(f"trying with valset: {valset_id}")
    assert valset_id > 0, "could not find valset"
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
            str(valset_id),
            "eth-main",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    print(process.args)

    stdout, stderr = process.communicate()

    stdout = str(stdout)
    stderr = str(stderr)

    if "item not found in store" in stdout or "item not found in store" in stderr:
        return get_valset(node, valset_id // 2)
    valset = json.loads(stdout)

    if len(valset.validators) == 0:
        return get_valset(node, valset_id + valset_id // 2)

    # validators are strings returned like this: "0xabcd...."
    return valset.validators, valset.powers, valset.valsetID


def main():
    node = sys.argv[1]
    assert node, "must provide 1 argument which is the node: e.g. tcp://localhost:26657"
    validators, powers, valset_id = get_valset(node)

    power_sum = sum(powers)

    assert power_sum >= 2863311530, f"not enough power to reach consensus: {power_sum}"

    acct = accounts.load("deployer_account")
    turnstone_id = b""  # should update
    Turnstone.deploy(
        encode_abi(["bytes32"], [turnstone_id]),
        [validators, powers, valset_id],
        {"from": acct},
    )


if __name__ == "__main__":
    main()
