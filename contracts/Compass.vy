#pragma version 0.3.10
#pragma optimize gas
#pragma evm-version shanghai

"""
@title Compass
@license MIT
@author Volume.Finance
@notice v1.2.0
"""

MAX_VALIDATORS: constant(uint256) = 200
MAX_PAYLOAD: constant(uint256) = 10240
MAX_BATCH: constant(uint256) = 64

POWER_THRESHOLD: constant(uint256) = 2_863_311_530 # 2/3 of 2^32, Validator powers will be normalized to sum to 2 ^ 32 in every valset update.
compass_id: public(immutable(bytes32))

interface ERC20:
    def balanceOf(_owner: address) -> uint256: view
    def transfer(_to: address, _value: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _value: uint256) -> bool: nonpayable

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
    relayer_fee: uint256 # Total amount to attribute to relayer
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
    receiver: String[64]
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

event BooksReceivedEvent:
    amount: uint256
    total_funds: uint256
    total_claims: uint256
    community_funds: uint256
    security_funds: uint256

event BooksSentEvent:
    amount: uint256
    receiver: address

last_compass: public(immutable(address))
last_checkpoint: public(bytes32)
last_valset_id: public(uint256)
last_event_id: public(uint256)
last_gravity_nonce: public(uint256)
last_batch_id: public(HashMap[address, uint256])
message_id_used: public(HashMap[uint256, bool])

# Rewards program
rewards_community_wallet: public(uint256) #stores the balance attributed to the community wallet
rewards_security_wallet: public(uint256) #stores the balance attributed to the security wallet
funds: public(HashMap[bytes32, uint256]) #stores the spendable balance of paloma addresses
claimable_rewards: public(HashMap[address, uint256]) #stores the claimable balance for eth addresses
total_funds: public(uint256) #stores the balance of total user funds
total_claims: public(uint256) # stores the balance of total claimable rewards

# compass_id: unique identifier for compass instance
# valset: initial validator set
@external
def __init__(_compass_id: bytes32, _last_compass: address, _event_id: uint256, _gravity_nonce:uint256, valset: Valset):
    compass_id = _compass_id
    last_compass = _last_compass
    cumulative_power: uint256 = 0
    i: uint256 = 0
    # check cumulative power is enough
    for validator in valset.validators:
        cumulative_power += valset.powers[i]
        if cumulative_power >= POWER_THRESHOLD:
            break
        i = unsafe_add(i, 1)
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"
    new_checkpoint: bytes32 = keccak256(_abi_encode(valset.validators, valset.powers, valset.valset_id, compass_id, method_id=method_id("checkpoint(address[],uint256[],uint256,bytes32)")))
    self.last_checkpoint = new_checkpoint
    self.last_valset_id = valset.valset_id
    self.last_event_id = _event_id
    self.last_gravity_nonce = _gravity_nonce
    log ValsetUpdated(new_checkpoint, valset.valset_id, _event_id)

# sends the current internal book keeping state to a new version of compass, along with all funds
# left on the contract.
# consensus: current validator set and signatures
# new_compass: address of new compass to which to send the funds
# message_id: unused message ID
# deadline: message deadline
# authority: intended message sender address
# gas_estimate: gas estimation in wei
@external
@nonreentrant('lock')
def send_books(consensus: Consensus, new_compass: address, message_id: uint256,deadline: uint256, authority: address, gas_estimate: uint256):
    self.assert_authority(authority, gas_estimate)
    assert not self.message_id_used[message_id], "Used Message_ID"
    self.message_id_used[message_id] = True
    # check if the supplied current validator set matches the saved checkpoint
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"
    # signing data is keccak256 hash of abi_encoded logic_call(args, message_id, compass_id, deadline)
    args_hash: bytes32 = keccak256(_abi_encode(new_compass, message_id, deadline, authority, gas_estimate, method_id=method_id("upgrade(address,uint256,uint256,address,uint256)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)
    # last fee reservation
    self.reserve_security_refund(authority, gas_estimate)
    self.assert_balance()
    # Make call 
    success, response = raw_call(
        new_compass,
        _abi_encode(self.funds, self.claimable_rewards, self.total_funds, self.total_claims, self.rewards_security_wallet, self.rewards_community_wallet, method_id=method_id("receive_books(HashMap[bytes32,uint256],HashMap[address,uint256],uint256,uint256,uint256,uint256)")),
        value=self.balance
        revert_on_failure=True
        )
    assert success, "failed to send books"
    self.funds = empty(HashMap[bytes32, uint256])
    self.claimable_rewards = empty(HashMap[address, uint256])
    self.total_funds = 0
    self.total_claims = 0
    self.rewards_security_wallet = 0
    self.rewards_community_wallet = 0
    self.assert_balance()
    log BooksSentEvent(_value, new_compass)
    return response

# Receives the internal book keeping state of the last version of compass, along with any funds
# left on the old contract.
# Can only be sent by the old version of compass.
@external
@payable
@nonreentrant('lock')
def receive_books(_funds:HashMap[bytes32, uint256], _claims:HashMap[address, uint256], _total_funds:uint256, _total_claims:uint256, _rewards_security_wallet:uint256, _rewards_community_wallet:uint256):
    assert msg.sender == _last_compass, "Invalid sender"
    assert msg.value == _total_funds + _total_claims + _rewards_security_wallet + _rewards_community_wallet, "Message value does not match books"
    self.funds = _funds
    self.claimable_rewards = _claims
    self.total_funds = _total_funds
    self.total_claims = _total_claims
    self.rewards_security_wallet = _rewards_security_wallet
    self.rewards_community_wallet = _rewards_community_wallet
    log BooksReceivedEvent(msg.value, self.funds, self.claimable_rewards, self.rewards_community_wallet, self.rewards_security_wallet)

# This updates the valset by checking that the validators in the current valset have signed off on the
# new valset. The signatures supplied are the signatures of the current valset over the checkpoint hash
# generated from the new valset.
# Anyone can call this function, but they must supply valid signatures of constant_powerThreshold of the current valset over
# the new valset.
# valset: new validator set to update with
# consensus: current validator set and signatures
# authority: intended message sender address
# gas_estimate: gas estimation in wei
@external
@nonreentrant('lock')
def update_valset(consensus: Consensus, new_valset: Valset, authority:address, gas_estimate: uint256):
    self.assert_authority(authority, gas_estimate)

    # longer be okay and validators will able to claim rewards that belong to others.
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
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"
    # check if the supplied current validator set matches the saved checkpoint
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"
    # calculate the new checkpoint
    new_checkpoint: bytes32 = self.make_checkpoint(new_valset)
    args_hash = keccak256(_abi_encode(new_checkpoint, authority, gas_estimate, method_id=method_id("update_valset(bytes32,address,uint256)")))
    # check if enough validators signed new validator set (new checkpoint)
    self.check_validator_signatures(consensus, args_hash)
    self.last_checkpoint = new_checkpoint
    self.last_valset_id = new_valset.valset_id
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = event_id

    self.reserve_security_refund(authority, gas_estimate) 
    self.assert_balance()
    log ValsetUpdated(new_checkpoint, new_valset.valset_id, event_id)

# This makes calls to contracts that execute arbitrary logic
# message_id is to prevent replay attack and every message_id can be used only once
# authority: intended message sender address
# gas_estimate: gas estimation in wei
@external
@nonreentrant('lock')
def submit_logic_call(consensus: Consensus, args: LogicCallArgs, fee_args: FeeArgs, message_id: uint256, deadline: uint256, authority: address):
    assert block.timestamp <= deadline, "Timeout"
    assert not self.message_id_used[message_id], "Used Message_ID"
    _total_fee = self.assert_fees(fee_args)
    self.message_id_used[message_id] = True
    # check if the supplied current validator set matches the saved checkpoint
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"
    # signing data is keccak256 hash of abi_encoded logic_call(args, message_id, compass_id, deadline)
    args_hash: bytes32 = keccak256(_abi_encode(args, fee_args, message_id, compass_id, deadline, method_id=method_id("logic_call((address,bytes),(uint256,uint256,uint256,bytes32),uint256,bytes32,uint256,address)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)
    # move fees
    self.transfer_fees(fee_args, _total_fee)
    self.assert_balance()
    # make call to logic contract
    raw_call(args.logic_contract_address, args.payload)
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = event_id
    log LogicCallEvent(args.logic_contract_address, args.payload, message_id, event_id)


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# B R I D G E
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# call to send the amount of TOKEN to Paloma.
# token: address of the TOKEN to send
# receiver: Paloma address to receive the funds
# amount: amount of TOKEN to send
@external
def send_token_to_paloma(token: address, receiver: String[64], amount: uint256):
    _balance: uint256 = ERC20(token).balanceOf(self)
    assert ERC20(token).transferFrom(msg.sender, self, amount, default_return_value=True), "TF fail"
    _balance = ERC20(token).balanceOf(self) - _balance
    assert _balance > 0, "Zero Transfer"
    _nonce: uint256 = unsafe_add(self.last_gravity_nonce, 1)
    self.last_gravity_nonce = _nonce
    _event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = _event_id
    log SendToPalomaEvent(token, msg.sender, receiver, amount, _nonce, _event_id)

# submit a new batch of brdige transation to compass.
# consensus: current validator set and signatures
# token: address of the TOKEN concerned with the transactions
# args: arguments of for the transactions
# batch_id: incremental batch nonce
# deadline: message deadline
# authority: intended message sender address
# gas_estimate: gas estimation in wei
@external
@nonreentrant('lock')
def submit_batch(consensus: Consensus, token: address, args: TokenSendArgs, batch_id: uint256, deadline: uint256, authority:address, gas_estimate: uint256):
    self.assert_authority(authority, gas_estimate)

    assert block.timestamp <= deadline, "Timeout"
    assert self.last_batch_id[token] < batch_id, "Wrong batch id"
    length: uint256 = len(args.receiver)
    assert length == len(args.amount), "Unmatched Params"
    # check if the supplied current validator set matches the saved checkpoint
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"
    # signing data is keccak256 hash of abi_encoded batch_call(args, batch_id, compass_id, deadline)
    args_hash: bytes32 = keccak256(_abi_encode(token, args, batch_id, compass_id, deadline, authority, gas_estimate, method_id=method_id("batch_call(address,(address[],uint256[]),uint256,bytes32,uint256,address,bytes32)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)
    # make call to logic contract
    for i in range(MAX_BATCH):
        if  i >= length:
            break
        assert ERC20(token).transfer(args.receiver[i], args.amount[i], default_return_value=True), "Tr fail"
    _nonce: uint256 = unsafe_add(self.last_gravity_nonce, 1)
    self.last_gravity_nonce = _nonce
    _event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = _event_id
    self.last_batch_id[token] = batch_id

    self.reserve_security_refund(authority, gas_estimate) 
    self.assert_balance()
    log BatchSendEvent(token, batch_id, _nonce, _event_id)

# deploys a new erc20 token to the chain
# must be called from compass itself.
@external
def deploy_erc20(_paloma_denom: String[64], _name: String[64], _symbol: String[32], _decimals: uint8, _blueprint: address):
    assert msg.sender == self, "Invalid"
    erc20: address = create_from_blueprint(_blueprint, self, _name, _symbol, _decimals, code_offset=3)
    event_id: uint256 = unsafe_add(self.last_event_id, 1)
    self.last_event_id = event_id
    log ERC20DeployedEvent(_paloma_denom, erc20, _name, _symbol, _decimals, event_id)



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
    # make sure we return any funds other than `amount`
    if msg.value > amount:
        send(msg.sender, unsafe_sub(msg.value, amount))
    else:
        assert msg.value == amount, "Insufficient deposit"

    self.funds[depositor_paloma_address] = unsafe_add(self.funds[depositor_paloma_address], amount)
    log FundsDepositedEvent(depositor_paloma_address, msg.sender, amount)

# Withdraw ramped up claimable rewards from compass. Withdrawals will be swapped and
# reimbursed in GRAIN.
# amount: the amount of COIN to withdraw.
# exchange: address of the DEX to use for exchanging the token
@external
@nonreentrant('lock')
def withdraw(amount:uint256, exchange: address):
    assert self.claimable_rewards[msg.sender] >= amount, "Missing claimable rewards"
    self.claimable_rewards[msg.sender] = self.claimable_rewards[msg.sender] - amount
    self.total_claims = self.total_claims - amount
    self.assert_balance()
    # TODO: Implement (Steven)
    # - exchange requested amount for GRAINS on given DEX
    # - send exchanged GRAINS to msg sender
    log FundsWithdrawnEvent(msg.sender, amount)


# Top up the security funds on the contract used to reimburse all infrastructure
# related messages. All sent value will be consumed.
@external
@payable
@nonreentrant('lock')
def security_fee_topup():
    assert msg.value > 0, "Insufficient deposit"
    # Make sure we check against overflow here
    self.rewards_security_wallet = self.rewards_security_wallet + msg.value


# Bridge the current balance of the community funds back to Paloma
# consensus: current validator set and signatures
# message_id: incremental unused message ID
# deadline: message deadline
# exchange: address of the DEX to use for exchanging the token
# receiver: Paloma address to receive the funds
# authority: intended message sender address
# gas_estimate: gas estimation in wei
@external
@nonreentrant('lock')
def bridge_community_tax_to_paloma(consensus: Consensus, message_id: uint256, deadline: uint256, exchange: address, receiver: byte32, authority: address, gas_estimate: uint256):
    self.assert_authority(authority, gas_estimate)

    assert block.timestamp <= deadline, "Timeout"
    assert not self.message_id_used[message_id], "Used Message_ID"
    self.message_id_used[message_id] = True

    # check if the supplied current validator set matches the saved checkpoint
    assert self.last_checkpoint == self.make_checkpoint(consensus.valset), "Incorrect Checkpoint"

    # signing data is keccak256 hash of abi_encoded logic_call(args, message_id, compass_id, deadline)
    args_hash: bytes32 = keccak256(_abi_encode(message_id, deadline, exchange, receiver, authority, gas_estimate, method_id=method_id("bridge_community_tax_to_paloma(uint256,uint256,address,byte32,address,uint256)")))
    # check if enough validators signed args_hash
    self.check_validator_signatures(consensus, args_hash)

    # TODO: Implement: (Steven)
    # - exchange `self.rewards_community_wallet` amount for GRAINS on DEX
    # - call `send_token_to_paloma`, send exchanged GRAINS to receiver address

    self.reserve_security_refund(authority, gas_estimate)
    self.assert_balance()


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# I N T E R N A L S
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

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
    assert cumulative_power >= POWER_THRESHOLD, "Insufficient Power"

# Make a new checkpoint from the supplied validator set
# A checkpoint is a hash of all relevant information about the valset. This is stored by the contract,
# instead of storing the information directly. This saves on storage and gas.
# The format of the checkpoint is:
# keccak256 hash of abi_encoded checkpoint(validators[], powers[], valset_id, compass_id)
# The validator powers must be decreasing or equal. This is important for checking the signatures on the
# next valset, since it allows the caller to stop verifying signatures once a quorum of signatures have been verified.
@internal
@pure
def make_checkpoint(valset: Valset) -> bytes32:
    return keccak256(_abi_encode(valset.validators, valset.powers, valset.valset_id, compass_id, method_id=method_id("checkpoint(address[],uint256[],uint256,bytes32)")))

@internal
def transfer_fees(fee_args: FeeArgs, total:uint256):
    self.claimable_rewards[fee_args.relayer] = unsafe_add(self.claimable_rewards[fee_args.relayer], fee_args.relayer_fee)
    self.rewards_community_wallet = unsafe_add(self.rewards_community_wallet, fee_args.community_fee)
    self.rewards_security_wallet = unsafe_add(self.rewards_security_wallet, fee_args.security_fee)
    self.funds[fee_args.fee_payer_paloma_address] = unsafe_sub(self.funds[fee_args.fee_payer_paloma_address], total)
    self.total_claims = unsafe_add(self.total_claims, fee_args.relayer_fee)
    self.total_funds = unsafe_sub(self.total_funds, total)

@internal
@view
def assert_fees(fee_args: FeeArgs) -> uint256:
    _total_fee:uint256 = fee_args.relayer_fee + fee_args.community_fee + fee_args.security_fee
    assert self.funds[fee_args.fee_payer_paloma_address] >= _total_fee, "Insufficient user funds to cover fees"
    return _total_fee

@internal
@pure
def assert_authority(authority: address, gas_estimate: uint256):
    assert authority == msg.sender, "Message sender unauthorized."
    # aviod reimbursing more than relayer was willing to pay
    assert msg.gas >= gas_estimate, "Insufficient funds to cover gas estimate"

@internal
def reserve_security_refund(sender: address, gas_estimate: uint256):
    # Refund is only covered while security wallet is funded.
    if self.rewards_security_wallet >= gas_estimate:
        self.rewards_security_wallet = unsafe_sub(self.rewards_security_wallet, gas_estimate)
        self.claimable_rewards[sender] = unsafe_add(self.claimable_rewards[sender], gas_estimate)
        self.total_claims = unsafe_add(self.total_claims, gas_estimate)

@internal
@view
def assert_balance():
    assert self.balance == self.total_claims + self.total_funds + self.rewards_security_wallet + self.rewards_community_wallet, "balance mismatch"

