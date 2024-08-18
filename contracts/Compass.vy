#pragma version 0.3.10
#pragma optimize gas
#pragma evm-version shanghai

"""
@title Compass
@license MIT
@author Volume.Finance
@notice v2.0.0
"""

MAX_VALIDATORS: constant(uint256) = 200
MAX_PAYLOAD: constant(uint256) = 10240
MAX_EVENT: constant(uint256) = 1024
MAX_BATCH: constant(uint256) = 64

POWER_THRESHOLD: constant(uint256) = 2_863_311_530 # 2/3 of 2^32, Validator powers will be normalized to sum to 2 ^ 32 in every valset update.
compass_id: public(immutable(bytes32))

interface ERC20:
    def balanceOf(_owner: address) -> uint256: view
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable

interface FeeManager:
    def deposit(depositor_paloma_address: bytes32): payable
    def withdraw(receiver: address, amount:uint256, dex: address, payload: Bytes[1028], min_grain: uint256): nonpayable
    def transfer_fees(fee_args: FeeArgs, relayer: address): nonpayable
    def security_fee_topup(): payable
    def reserve_security_fee(sender: address, gas_fee_amount: uint256): nonpayable
    def bridge_community_fee_to_paloma(amount: uint256, dex: address, payload: Bytes[1028], min_grain: uint256) -> (address, uint256): nonpayable
    def update_compass(_new_compass: address): nonpayable

interface Compass:
    def FEE_MANAGER() -> address: view

interface Deployer:
    def deployFromBytecode(_bytecode: Bytes[24576]) -> address: nonpayable

struct Valset:
    validators: DynArray[address, MAX_VALIDATORS] # Validator addresses
    powers: DynArray[uint256, MAX_VALIDATORS] # Powers of given validators, in the same order as validators array
    valset_id: uint256 # nonce of this validator set

struct Signature:
    v: uint256
    r: uint256
    s: uint256

struct Consensus:
    valset: Valset # Valset data
    signatures: DynArray[Signature, MAX_VALIDATORS] # signatures in the same order as validator array in valset

struct LogicCallArgs:
    logic_contract_address: address # the arbitrary contract address to external call
    payload: Bytes[MAX_PAYLOAD] # payloads

struct TokenSendArgs:
    receiver: DynArray[address, MAX_BATCH]
    amount: DynArray[uint256, MAX_BATCH]

struct FeeArgs:
    relayer_fee: uint256 # Total amount to alot for relayer
    community_fee: uint256 # Total amount to alot for community wallet
    security_fee: uint256 # Total amount to alot for security wallet
    fee_payer_paloma_address: bytes32 # Paloma address covering the fees

event ValsetUpdated:
    checkpoint: bytes32
    valset_id: uint256
    event_id: uint256

event LogicCallEvent:
    logic_contract_address: address
    payload: Bytes[MAX_PAYLOAD]
    message_id: uint256
    event_id: uint256

event SendToPalomaEvent:
    token: address
    sender: address
    receiver: bytes32
    amount: uint256
    nonce: uint256
    event_id: uint256

event BatchSendEvent:
    token: address
    batch_id: uint256
    nonce: uint256
    event_id: uint256

event ERC20DeployedEvent:
    paloma_denom: String[64]
    token_contract: address
    name: String[64]
    symbol: String[32]
    decimals: uint8
    event_id: uint256

event FundsDepositedEvent:
    depositor_paloma_address: bytes32
    sender: address
    amount: uint256

event FundsWithdrawnEvent:
    receiver: address
    amount: uint256

event UpdateCompass:
    contract_address: address
    payload: Bytes[MAX_PAYLOAD]
    event_id: uint256

event NodeSaleEvent:
    contract_address: address
    buyer: address
    paloma: bytes32
    node_count: uint256
    grain_amount: uint256
    nonce: uint256
    event_id: uint256

event ContractDeployed:
    child: address
    deployer: address
    event_id: uint256

last_checkpoint: public(bytes32)
last_valset_id: public(uint256)
last_event_id: public(uint256)
last_gravity_nonce: public(uint256)
last_batch_id: public(HashMap[address, uint256])
message_id_used: public(HashMap[uint256, bool])
slc_switch: public(bool)
FEE_MANAGER: public(immutable(address))

# compass_id: unique identifier for compass instance
# valset: initial validator set
@external
def __init__(_compass_id: bytes32, _event_id: uint256, _gravity_nonce:uint256, valset: Valset, fee_manager: address, _deployer_contract: address):
    compass_id = _compass_id
    cumulative_power: uint256 = 0
    i: uint256 = 0
    # check cumulative power is enough
    for validator in valset.validators:
        cumulative_power += valset.powers[i]
        if cumulative_power >= POWER_THRESHOLD:
            break
        i = unsafe_add(i, 1)
    self.power_check(cumulative_power)
    new_checkpoint: bytes32 = keccak256(_abi_encode(valset.validators, valset.powers, valset.valset_id, compass_id, method_id=method_id("checkpoint(address[],uint256[],uint256,bytes32)")))
    self.last_checkpoint = new_checkpoint
    self.last_valset_id = valset.valset_id
    self.last_event_id = _event_id
    self.last_gravity_nonce = _gravity_nonce
    FEE_MANAGER = fee_manager
    log ValsetUpdated(new_checkpoint, valset.valset_id, _event_id)

# check if cumulated power is enough
@internal
def power_check(cumulative_power: uint256):
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"


# utility function to verify EIP712 signature
@internal
@pure
def verify_signature(signer: address, hash: bytes32, sig: Signature) -> bool:
    message_digest: bytes32 = keccak256(concat(convert("\x19Ethereum Signed Message:\n32", Bytes[28]), hash))
    return signer == ecrecover(message_digest, sig.v, sig.r, sig.s)

# consensus: validator set and signatures
# hash: what we are checking they have signed
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
        i = unsafe_add(i, 1)
    self.power_check(cumulative_power)

# Make a new checkpoint from the supplied validator set
# A checkpoint is a hash of all relevant information about the valset. This is stored by the contract,
# instead of storing the information directly. This saves on storage and gas.
# The format of the checkpoint is:
# keccak256 hash of abi_encoded checkpoint(validators[], powers[], valset_id, compass_id)
# The validator powers must be decreasing or equal. This is important for checking the signatures on the
# next valset, since it allows the caller to stop verifying signatures once a quorum of signatures have been verified.
@internal
@view
def make_checkpoint(valset: Valset) -> bytes32:
    return keccak256(_abi_encode(valset.validators, valset.powers, valset.valset_id, compass_id, method_id=method_id("checkpoint(address[],uint256[],uint256,bytes32)")))

# check if the gas estimate is too big
@internal
def gas_check(gas_estimate: uint256):
    assert msg.gas >= gas_estimate, "Insufficient funds to cover gas estimate"

@internal
def deadline_check(deadline: uint256):
    assert block.timestamp <= deadline, "Timeout"

@internal
def reserve_security_fee(relayer: address, gas_estimate: uint256):
    self.gas_check(gas_estimate)
    FeeManager(FEE_MANAGER).reserve_security_fee(relayer, gas_estimate)

@internal
def check_checkpoint(checkpoint: bytes32):
    assert self.last_checkpoint == checkpoint, "Incorrect Checkpoint"

# This updates the valset by checking that the validators in the current valset have signed off on the
# new valset. The signatures supplied are the signatures of the current valset over the checkpoint hash
# generated from the new valset.
# Anyone can call this function, but they must supply valid signatures of constant_powerThreshold of the current valset over
# the new valset.
# valset: new validator set to update with
# consensus: current validator set and signatures
@external
def update_valset(consensus: Consensus, new_valset: Valset, relayer: address, gas_estimate: uint256):
    self.reserve_security_fee(relayer, gas_estimate)
    # check if new valset_id is greater than current valset_id
    assert new_valset.valset_id > consensus.valset.valset_id, "Invalid Valset ID"
    cumulative_power: uint256 = 0
    i: uint256 = 0
    # check cumulative power is enough
    for validator in new_valset.validators:
        cumulative_power += new_valset.powers[i]
        if cumulative_power >= POWER_THRESHOLD:
            break
        i = unsafe_add(i, 1)
    self.power_check(cumulative_power)
    # check if the supplied current validator set matches the saved checkpoint
    self.check_checkpoint(self.make_checkpoint(consensus.valset))
    # calculate the new checkpoint
    new_checkpoint: bytes32 = self.make_checkpoint(new_valset)
    args_hash: bytes32 = keccak256(_abi_encode(new_checkpoint, relayer, gas_estimate, method_id=method_id("update_valset(bytes32,address,uint256)")))
    # check if enough validators signed new validator set (new checkpoint)
    self.check_validator_signatures(consensus, args_hash)
    self.last_checkpoint = new_checkpoint
    self.last_valset_id = new_valset.valset_id
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = event_id
    log ValsetUpdated(new_checkpoint, new_valset.valset_id, event_id)

# This makes calls to contracts that execute arbitrary logic
# message_id is to prevent replay attack and every message_id can be used only once
@external
def submit_logic_call(consensus: Consensus, args: LogicCallArgs, fee_args: FeeArgs, message_id: uint256, deadline: uint256, relayer: address):
    FeeManager(FEE_MANAGER).transfer_fees(fee_args, relayer)
    self.deadline_check(deadline)
    assert not self.message_id_used[message_id], "Used Message_ID"
    self.message_id_used[message_id] = True
    # check if the supplied current validator set matches the saved checkpoint
    self.check_checkpoint(self.make_checkpoint(consensus.valset))
    # signing data is keccak256 hash of abi_encoded logic_call(args, fee_args, message_id, compass_id, deadline, relayer)
    args_hash: bytes32 = keccak256(_abi_encode(args, fee_args, message_id, compass_id, deadline, relayer, method_id=method_id("logic_call((address,bytes),(uint256,uint256,uint256,bytes32),uint256,bytes32,uint256,address)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)
    # make call to logic contract
    self.slc_switch = True
    raw_call(args.logic_contract_address, args.payload)
    self.slc_switch = False
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = event_id
    log LogicCallEvent(args.logic_contract_address, args.payload, message_id, event_id)

@internal
def _send_token_to_paloma(token: address, receiver: bytes32, amount: uint256):
    _nonce: uint256 = unsafe_add(self.last_gravity_nonce, 1)
    self.last_gravity_nonce = _nonce
    _event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = _event_id
    log SendToPalomaEvent(token, msg.sender, receiver, amount, _nonce, _event_id)

@external
def send_token_to_paloma(token: address, receiver: bytes32, amount: uint256):
    _balance: uint256 = ERC20(token).balanceOf(self)
    assert ERC20(token).transferFrom(msg.sender, self, amount, default_return_value=True), "failed TransferFrom"
    _balance = ERC20(token).balanceOf(self) - _balance
    self._send_token_to_paloma(token, receiver, _balance)

@external
def submit_batch(consensus: Consensus, token: address, args: TokenSendArgs, batch_id: uint256, deadline: uint256, relayer: address, gas_estimate: uint256):
    self.reserve_security_fee(relayer, gas_estimate)
    self.deadline_check(deadline)
    assert self.last_batch_id[token] < batch_id, "Wrong batch id"
    length: uint256 = len(args.receiver)
    assert length == len(args.amount), "Unmatched Params"
    # check if the supplied current validator set matches the saved checkpoint
    self.check_checkpoint(self.make_checkpoint(consensus.valset))
    # signing data is keccak256 hash of abi_encoded batch_call(args, batch_id, compass_id, deadline, relayer, gas_estimate)
    args_hash: bytes32 = keccak256(_abi_encode(token, args, batch_id, compass_id, deadline, relayer, gas_estimate, method_id=method_id("batch_call(address,(address[],uint256[]),uint256,bytes32,uint256,address,uint256)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)
    # make call to logic contract
    for i in range(MAX_BATCH):
        if  i >= length:
            break
        assert ERC20(token).transfer(args.receiver[i], args.amount[i], default_return_value=True), "failed transfer"
    _nonce: uint256 = unsafe_add(self.last_gravity_nonce, 1)
    self.last_gravity_nonce = _nonce
    _event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = _event_id
    self.last_batch_id[token] = batch_id
    log BatchSendEvent(token, batch_id, _nonce, _event_id)

@external
def emit_nodesale_event(buyer: address, paloma: bytes32, node_count: uint256, grain_amount: uint256):
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = event_id
    _nonce: uint256 = unsafe_add(self.last_gravity_nonce, 1)
    self.last_gravity_nonce = _nonce
    log NodeSaleEvent(msg.sender, buyer, paloma, node_count, grain_amount, _nonce, event_id)

@external
def deploy_erc20(_paloma_denom: String[64], _name: String[64], _symbol: String[32], _decimals: uint8, _blueprint: address):
    assert msg.sender == self, "Invalid"
    erc20: address = create_from_blueprint(_blueprint, self, _name, _symbol, _decimals, code_offset=3)
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = event_id
    log ERC20DeployedEvent(_paloma_denom, erc20, _name, _symbol, _decimals, event_id)

@external
@view
def arbitrary_view(contract_address: address, payload: Bytes[1024]) -> Bytes[1024]:
    return raw_call(contract_address, payload, is_static_call=True, max_outsize=1024)


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# F E E S
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# Deposit some balance on the contract to be used when sending messages from Paloma.
# depositor_paloma_address: paloma address to which to attribute the sent amount
# amount: amount of COIN to register with compass. Overpaid balance will be sent back.
@external
@payable
@nonreentrant('lock')
def deposit(depositor_paloma_address: bytes32, amount: uint256):
    if msg.value > amount:
        send(msg.sender, unsafe_sub(msg.value, amount))
    else:
        assert amount == msg.value, "Insufficient deposit"
    FeeManager(FEE_MANAGER).deposit(depositor_paloma_address, value=amount)
    log FundsDepositedEvent(depositor_paloma_address, msg.sender, amount)

# Withdraw ramped up claimable rewards from compass. Withdrawals will be swapped and
# reimbursed in GRAIN.
# amount: the amount of COIN to withdraw.
# dex: address of the DEX to use for exchanging the token
# payload: the function payload to exchange ETH to grain for the dex
# min_grain: expected grain amount getting from dex to prevent front-running(high slippage / sandwich attack)
@external
def withdraw(amount:uint256, dex: address, payload: Bytes[1028], min_grain: uint256):
    FeeManager(FEE_MANAGER).withdraw(msg.sender, amount, dex, payload, min_grain)
    log FundsWithdrawnEvent(msg.sender, amount)

# Top up the security funds on the contract used to reimburse all infrastructure
# related messages. All sent value will be consumed.
@external
@payable
@nonreentrant('lock')
def security_fee_topup(amount: uint256):
    if msg.value > amount:
        send(msg.sender, unsafe_sub(msg.value, amount))
    else:
        assert amount == msg.value, "Insufficient deposit"
    # Make sure we check against overflow here
    FeeManager(FEE_MANAGER).security_fee_topup(value=amount)

# Bridge the current balance of the community funds back to Paloma
# consensus: current validator set and signatures
# message_id: incremental unused message ID
# deadline: message deadline
# receiver: Paloma address to receive the funds
# relayer: relayer address
# gas_estimate: gas amount estimation
# amount: Ete amount to swap and bridge
# dex: address of the DEX to use for exchanging the Eth
# payload: the function payload to exchange ETH to grain for the dex
# min_grain: expected grain amount getting from dex to prevent front-running(high slippage / sandwich attack)
@external
@nonreentrant('lock')
def bridge_community_tax_to_paloma(consensus: Consensus, message_id: uint256, deadline: uint256, receiver: bytes32, relayer: address, gas_estimate: uint256, amount:uint256, dex: address, payload: Bytes[1028], min_grain: uint256):
    self.reserve_security_fee(relayer, gas_estimate)
    self.deadline_check(deadline)
    assert not self.message_id_used[message_id], "Used Message_ID"
    self.message_id_used[message_id] = True

    # check if the supplied current validator set matches the saved checkpoint
    self.check_checkpoint(self.make_checkpoint(consensus.valset))

    # signing data is keccak256 hash of abi_encoded logic_call(args, message_id, compass_id, deadline)
    args_hash: bytes32 = keccak256(_abi_encode(message_id, deadline, receiver, relayer, gas_estimate, amount, dex, payload,  min_grain, method_id=method_id("bridge_community_tax_to_paloma(uint256,uint256,byte32,address,uint256,uint256,address,bytes,uint256)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)

    grain: address = empty(address)
    grain_balance: uint256 = 0
    grain, grain_balance = FeeManager(FEE_MANAGER).bridge_community_fee_to_paloma(amount, dex, payload, min_grain)
    self._send_token_to_paloma(grain, receiver, grain_balance)

# This function is to update compass address in contracts. After running this function, This Compass-evm can't be used anymore.
# consensus: current validator set and signatures
# update_compass_args: array of LogicCallArgs to update compass address in contracts
# deadline: message deadline
# gas_estimate: gas amount estimation
# relayer: relayer address

@external
def compass_update_batch(consensus: Consensus, update_compass_args: DynArray[LogicCallArgs, MAX_BATCH], deadline: uint256, gas_estimate: uint256, relayer: address):
    self.reserve_security_fee(relayer, gas_estimate)
    self.deadline_check(deadline)
    # check if the supplied current validator set matches the saved checkpoint
    self.check_checkpoint(self.make_checkpoint(consensus.valset))
    # signing data is keccak256 hash of abi_encoded logic_call(args, message_id, compass_id, deadline)
    args_hash: bytes32 = keccak256(_abi_encode(update_compass_args, deadline, relayer, gas_estimate, method_id=method_id("compass_update_batch((address,bytes)[],uint256,address,uint256)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    for i in range(MAX_BATCH):
        if i >= len(update_compass_args):
            break
        raw_call(update_compass_args[i].logic_contract_address, update_compass_args[i].payload)
        event_id = unsafe_add(event_id, 1)
        log UpdateCompass(update_compass_args[0].logic_contract_address, update_compass_args[0].payload, event_id)
    self.last_event_id = event_id

@external
def deploy_contract(consensus: Consensus, _deployer: address, _bytecode: Bytes[24576], fee_args: FeeArgs, message_id: uint256, deadline: uint256, relayer: address):
    FeeManager(FEE_MANAGER).transfer_fees(fee_args, relayer)
    self.deadline_check(deadline)
    assert not self.message_id_used[message_id], "Used Message_ID"
    self.message_id_used[message_id] = True
    # check if the supplied current validator set matches the saved checkpoint
    self.check_checkpoint(self.make_checkpoint(consensus.valset))
    # signing data is keccak256 hash of abi_encoded deploy_contract(bytecode, fee_args, message_id, compass_id, deadline, relayer)
    args_hash: bytes32 = keccak256(_abi_encode(_deployer, _bytecode, fee_args, message_id, compass_id, deadline, relayer, method_id=method_id("deploy_contract(address,bytes,(uint256,uint256,uint256,bytes32),uint256,bytes32,uint256,address)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)
    # make call to logic contract
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    child: address = Deployer(_deployer).deployFromBytecode(_bytecode)
    self.last_event_id = event_id
    log ContractDeployed(child, _deployer, event_id)
