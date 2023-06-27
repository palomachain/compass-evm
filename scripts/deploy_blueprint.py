from brownie import accounts, PalomaERC20
from typing import Union


def main():
    acct = accounts.load("deployer_account")
    initcode = get_blueprint_initcode(PalomaERC20.bytecode)
    tx = acct.transfer(data=initcode)
    print(tx.contract_address)

def get_blueprint_initcode(initcode: Union[str, bytes]):
    if isinstance(initcode, str):
        initcode = bytes.fromhex(initcode[2:])
    initcode = b"\xfe\x71\x00" + initcode
    initcode = (
        b"\x61" + len(initcode).to_bytes(2, "big") +
        b"\x3d\x81\x60\x0a\x3d\x39\xf3" + initcode
    )
    return initcode
