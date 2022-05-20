# @version 0.3.3
"""
@title Turnstone
@author Volume.Finance
"""

MAX_VALIDATORS: constant(uint256) = 128
MAX_BATCH: constant(uint256) = 128
POWER_THRESHOLD: constant(uint256) = 2_863_311_530 # 2/3 of 2^32
TURNSTONE_ID: immutable(bytes32)

struct ValsetArgs:
    validators: DynArray[address, MAX_VALIDATORS]
    powers: DynArray[uint256, MAX_VALIDATORS]
    nonce: uint256

struct LogicCallArgs:
    logicContractAddress: address
    payload: Bytes[1024]

struct Signature:
    v: uint256
    r: uint256
    s: uint256

event UpdateCheckpoint:
    new_checkpoint: bytes32

last_checkpoint: public(bytes32)
last_valset_nonce: public(uint256)

@external
def __init__(turnstone_id: bytes32, validators: DynArray[address, MAX_VALIDATORS], powers: DynArray[uint256, MAX_VALIDATORS]):
    TURNSTONE_ID = turnstone_id
    cumulative_power: uint256 = 0
    i: uint256 = 0
    for validator in validators:
        cumulative_power += powers[i]
        if cumulative_power >= POWER_THRESHOLD:
            break
        i += 1
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"
    valset_args: ValsetArgs = ValsetArgs({validators: validators, powers: powers, nonce: 0})
    self.last_valset_nonce = 0
    new_checkpoint: bytes32 = keccak256(_abi_encode(valset_args.validators, valset_args.powers, method_id=method_id("checkpoint(address[],uint256[])")))
    self.last_checkpoint = new_checkpoint

@external
@pure
def turnstone_id() -> bytes32:
    return TURNSTONE_ID

@internal
@pure
def verify_signature(signer: address, hash: bytes32, sig: Signature) -> bool:
    message_digest: bytes32 = keccak256(concat(convert("\x19EthereumSignedMessage:\n32", Bytes[26]), hash))
    return signer == ecrecover(message_digest, sig.v, sig.r, sig.s)

@internal
def check_validator_signatures(current_valset: ValsetArgs, sigs: DynArray[Signature, MAX_VALIDATORS], hash: bytes32):
    i: uint256 = 0
    cumulative_power: uint256 = 0
    for sig in sigs:
        if sig.v != 0:
            assert self.verify_signature(current_valset.validators[i], hash, sig), "Invalid Signature"
            cumulative_power += current_valset.powers[i]
            if cumulative_power >= POWER_THRESHOLD:
                break
        i += 1
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"

@internal
@view
def make_checkpoint(valset_args: ValsetArgs) -> bytes32:
    return keccak256(_abi_encode(valset_args.validators, valset_args.powers, valset_args.nonce, TURNSTONE_ID, method_id=method_id("checkpoint(address[],uint256[],uint256,bytes32)")))

@external
def update_valset(new_valset: ValsetArgs, current_valset: ValsetArgs, sigs: DynArray[Signature, MAX_VALIDATORS]):
    assert new_valset.nonce > current_valset.nonce, "Invalid Valset Nonce"
    cumulative_power: uint256 = 0
    i: uint256 = 0
    for validator in new_valset.validators:
        cumulative_power += new_valset.powers[i]
        if cumulative_power >= POWER_THRESHOLD:
            break
        i += 1
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"
    assert self.last_checkpoint == self.make_checkpoint(current_valset), "Incorrect Checkpoint"
    new_checkpoint: bytes32 = self.make_checkpoint(new_valset)
    self.check_validator_signatures(current_valset, sigs, new_checkpoint)
    self.last_checkpoint = new_checkpoint

@external
def submit_logic_call(current_valset: ValsetArgs, sigs: DynArray[Signature, MAX_VALIDATORS], args: LogicCallArgs, message_id: uint256, deadline: uint256):
    assert block.timestamp <= deadline, "Timeout"
    assert self.last_checkpoint == self.make_checkpoint(current_valset), "Incorrect Checkpoint"
    args_hash: bytes32 = keccak256(_abi_encode(args, message_id, deadline, method_id=method_id("logic_call((address,bytes),uint256,uint256)")))
    self.check_validator_signatures(current_valset, sigs, args_hash)
    raw_call(args.logicContractAddress, args.payload)

@external
def submit_batch_call(current_valset: ValsetArgs, sigs: DynArray[Signature, MAX_VALIDATORS], args: DynArray[LogicCallArgs, MAX_BATCH], message_id: uint256, deadline: uint256):
    assert block.timestamp <= deadline, "Timeout"
    assert self.last_checkpoint == self.make_checkpoint(current_valset), "Incorrect Checkpoint"
    args_hash: bytes32 = keccak256(_abi_encode(args, message_id, deadline, method_id=method_id("batch_logic_call((address,bytes)[],uint256,uint256)")))
    self.check_validator_signatures(current_valset, sigs, args_hash)
    for arg in args:
        raw_call(arg.logicContractAddress, arg.payload)