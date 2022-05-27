# @version 0.3.3
"""
@title Turnstone
@author Volume.Finance
"""

MAX_VALIDATORS: constant(uint256) = 128
MAX_BATCH: constant(uint256) = 128

POWER_THRESHOLD: constant(uint256) = 2_863_311_530 # 2/3 of 2^32, Validator powers will be normalized to sum to 2 ^ 32 in every valset update.
TURNSTONE_ID: immutable(bytes32)

struct Valset:
    validators: DynArray[address, MAX_VALIDATORS]
    powers: DynArray[uint256, MAX_VALIDATORS]
    valset_id: uint256

struct Signature:
    v: uint256
    r: uint256
    s: uint256

struct Consensus:
    valset: Valset
    signatures: DynArray[Signature, MAX_VALIDATORS]

struct LogicCallArgs:
    logicContractAddress: address
    payload: Bytes[1024]

last_checkpoint: public(bytes32)
_message_id_used: HashMap[uint256, bool]

@external
def __init__(turnstone_id: bytes32, valset: Valset):
    TURNSTONE_ID = turnstone_id
    cumulative_power: uint256 = 0
    i: uint256 = 0
    for validator in valset.validators:
        cumulative_power += valset.powers[i]
        if cumulative_power >= POWER_THRESHOLD:
            break
        i += 1
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"
    new_checkpoint: bytes32 = keccak256(_abi_encode(valset.validators, valset.powers, valset.valset_id, turnstone_id, method_id=method_id("checkpoint(address[],uint256[],uint256,bytes32)")))
    self.last_checkpoint = new_checkpoint

@external
@pure
def turnstone_id() -> bytes32:
    return TURNSTONE_ID

@internal
@pure
def verify_signature(signer: address, hash: bytes32, sig: Signature) -> bool:
    message_digest: bytes32 = keccak256(concat(convert("\x19Ethereum Signed Message:\n32", Bytes[28]), hash))
    return signer == ecrecover(message_digest, sig.v, sig.r, sig.s)

@internal
def check_validator_signatures(consensus: Consensus, hash: bytes32):
    i: uint256 = 0
    cumulative_power: uint256 = 0
    for sig in consensus.signatures:
        if sig.v != 0:
            assert self.verify_signature(consensus.valset.validators[i], hash, sig), "Invalid Signature"
            cumulative_power += consensus.valset.powers[i]
            if cumulative_power >= POWER_THRESHOLD:
                break
        i += 1
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"

@internal
@view
def make_checkpoint(valset: Valset) -> bytes32:
    return keccak256(_abi_encode(valset.validators, valset.powers, valset.valset_id, TURNSTONE_ID, method_id=method_id("checkpoint(address[],uint256[],uint256,bytes32)")))

@external
def update_valset(new_valset: Valset, consensus: Consensus):
    assert new_valset.valset_id > consensus.valset.valset_id, "Invalid Valset ID"
    cumulative_power: uint256 = 0
    i: uint256 = 0
    for validator in new_valset.validators:
        cumulative_power += new_valset.powers[i]
        if cumulative_power >= POWER_THRESHOLD:
            break
        i += 1
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"
    new_checkpoint: bytes32 = self.make_checkpoint(new_valset)
    self.check_validator_signatures(consensus, new_checkpoint)
    self.last_checkpoint = new_checkpoint

@external
def submit_logic_call(consensus: Consensus, args: LogicCallArgs, message_id: uint256, deadline: uint256):
    assert block.timestamp <= deadline, "Timeout"
    assert not self._message_id_used[message_id], "Used Message_ID"
    self._message_id_used[message_id] = True
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"
    args_hash: bytes32 = keccak256(_abi_encode(args, message_id, deadline, method_id=method_id("logic_call((address,bytes),uint256,uint256)")))
    self.check_validator_signatures(consensus, args_hash)
    raw_call(args.logicContractAddress, args.payload)

@external
def submit_batch_call(consensus: Consensus, args: DynArray[LogicCallArgs, MAX_BATCH], message_id: uint256, deadline: uint256):
    assert block.timestamp <= deadline, "Timeout"
    assert not self._message_id_used[message_id], "Used Message_ID"
    self._message_id_used[message_id] = True
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"
    args_hash: bytes32 = keccak256(_abi_encode(args, message_id, deadline, method_id=method_id("batch_logic_call((address,bytes)[],uint256,uint256)")))
    self.check_validator_signatures(consensus, args_hash)
    for arg in args:
        raw_call(arg.logicContractAddress, arg.payload)