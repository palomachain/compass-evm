import json
import subprocess

from brownie import Turnstone, accounts
from eth_abi import encode_abi


def get_valset(node, valset_id=None):
    if valset_id is None:
        valset_id = 99999999
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

    stdout, stderr = process.communicate()

    stdout = stdout.read()
    stderr = stderr.read()

    if "item not found in store" in stdout or "item not found in store" in stderr:
        return get_valset(node, valset_id // 2)
    valset = json.loads(stdout)

    if len(valset.validators) == 0:
        return get_valset(node, valset_id + valset_id // 2)

    # validators are strings returned like this: "0xabcd...."
    return valset.validators, valset.powers, valset.valsetID


def main():
    validators, powers, valset_id = get_valset("tcp://localhost:26657")
    acct = accounts.load("deployer_account")
    turnstone_id = b""  # should update
    Turnstone.deploy(
        encode_abi(["bytes32"], [turnstone_id]),
        [validators, powers, valset_id],
        {"from": acct},
    )


if __name__ == "__main__":
    main()
