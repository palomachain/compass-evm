#pragma version 0.3.10
#pragma optimize gas
#pragma evm-version shanghai

"""
@title Compass Fee Manager
@license MIT
@author Volume.Finance
@notice v1.0.0
"""

interface ERC20:
    def balanceOf(account: address) -> uint256: view
    def transfer(to: address, amount: uint256): nonpayable

interface Compass:
    def slc_switch() -> bool: view

struct FeeArgs:
    relayer_fee: uint256 # Total amount to alot for relayer
    community_fee: uint256 # Total amount to alot for community wallet
    security_fee: uint256 # Total amount to alot for security wallet
    fee_payer_paloma_address: bytes32 # Paloma address covering the fees

event Deposit:
    depositor_paloma_address: bytes32
    amount: uint256

event Withdraw:
    receiver: address
    amount: uint256

event SecurityFeeTopup:
    amount: uint256

event FeeTransfer:
    fee_payer_paloma_address: bytes32
    community_fee: uint256
    security_fee: uint256
    relayer_fee: uint256
    relayer: address

event ReserveSecurityFee:
    sender: address
    gas_fee_amount: uint256

event BridgeCommunityFeeToPaloma:
    amount: uint256

event UpdateCompass:
    new_compass: address

event InitializeCompass:
    compass: address

event InitializeGrain:
    grain: address

compass: public(address) # compass-evm address
grain: public(address) # grain token address
DEPLOYER: immutable(address)

# Rewards program
rewards_community_balance: public(uint256) # stores the balance attributed to the community wallet
rewards_security_balance: public(uint256) # stores the balance attributed to the security wallet
funds: public(HashMap[bytes32, uint256]) # stores the spendable balance of paloma addresses
claimable_rewards: public(HashMap[address, uint256]) # stores the claimable balance for eth addresses
total_funds: public(uint256) # stores the balance of total user funds # Steven: Why do we need this?
total_claims: public(uint256) # stores the balance of total claimable rewards # Steven: Why do we need this?

@external
def __init__():
    DEPLOYER = msg.sender

@internal
def compass_check(_compass: address):
    assert msg.sender == _compass, "Not Compass"
    assert not Compass(_compass).slc_switch(), "SLC is unavailable"

@external
@payable
def deposit(depositor_paloma_address: bytes32):
    # Deposit some balance on the contract to be used when sending messages from Paloma.
    # depositor_paloma_address: paloma address to which to attribute the sent amount
    self.compass_check(self.compass)
    self.funds[depositor_paloma_address] = unsafe_add(self.funds[depositor_paloma_address], msg.value)
    self.total_funds = unsafe_add(self.total_funds, msg.value)
    log Deposit(depositor_paloma_address, msg.value)

@internal
def swap_grain(_grain: address, amount:uint256, dex: address, payload: Bytes[1028], min_grain: uint256) -> uint256:
    assert min_grain > 0, "Min grain must be greater than 0"
    grain_balance: uint256 = ERC20(_grain).balanceOf(self)
    raw_call(dex, payload, value=amount)
    grain_balance = ERC20(_grain).balanceOf(self) - grain_balance
    assert grain_balance >= min_grain, "Insufficient grain received"
    return grain_balance

@external
@nonreentrant('lock')
def withdraw(receiver: address, amount:uint256, dex: address, payload: Bytes[1028], min_grain: uint256):
    # Withdraw ramped up claimable rewards from compass. Withdrawals will be swapped and
    # reimbursed in GRAIN.
    # receiver: the validator address to receive grain token
    # amount: the amount of COIN to withdraw.
    # dex: address of the DEX to use for exchanging the token
    # payload: the function payload to exchange ETH to grain for the dex
    # min_grain: expected grain amount getting from dex to prevent front-running(high slippage / sandwich attack)
    _compass: address = self.compass
    self.compass_check(_compass)
    self.claimable_rewards[receiver] = unsafe_sub(self.claimable_rewards[receiver], amount)
    self.total_claims = self.total_claims - amount
    assert self.claimable_rewards[receiver] >= amount, "Missing claimable rewards"
    _grain: address = self.grain
    grain_balance: uint256 = self.swap_grain(_grain, amount, dex, payload, min_grain)
    ERC20(_grain).transfer(receiver, grain_balance)
    log Withdraw(receiver, grain_balance)

@external
@payable
def security_fee_topup():
    _compass: address = self.compass
    self.compass_check(_compass)
    # Top up the security wallet with the given amount.
    self.rewards_security_balance = unsafe_add(self.rewards_security_balance, msg.value)
    log SecurityFeeTopup(msg.value)

@external
def transfer_fees(fee_args: FeeArgs, relayer: address):
    # Transfer fees to the community and security wallets.
    # fee_args: the FeeArgs struct containing the fee amounts.
    # relayer_fee: fee to message relayer
    # relayer: relayer address
    _community_fee: uint256 = fee_args.community_fee * tx.gasprice
    _security_fee: uint256 = fee_args.security_fee * tx.gasprice
    _relayer_fee: uint256 = fee_args.relayer_fee * tx.gasprice
    _total_fee: uint256 = _community_fee + _security_fee + _relayer_fee
    _compass: address = self.compass
    self.compass_check(_compass)
    self.rewards_community_balance = unsafe_add(self.rewards_community_balance, _community_fee)
    self.rewards_security_balance = unsafe_add(self.rewards_security_balance, _security_fee)
    self.claimable_rewards[relayer] = unsafe_add(self.claimable_rewards[relayer], _relayer_fee)
    user_remaining_funds: uint256 = self.funds[fee_args.fee_payer_paloma_address]
    assert user_remaining_funds >= _total_fee, "Insufficient funds"
    self.funds[fee_args.fee_payer_paloma_address] = unsafe_sub(user_remaining_funds, _total_fee)
    self.total_claims = unsafe_add(self.total_claims, _relayer_fee)
    self.total_funds = unsafe_sub(self.total_funds, _total_fee)
    log FeeTransfer(fee_args.fee_payer_paloma_address, _community_fee, _security_fee, _relayer_fee, relayer)

@external
def reserve_security_fee(sender: address, gas_fee_amount: uint256):
    # increase funds for relayer who ran other functions than SLC
    # sender: transaction sender address
    # gas_fee: gas fee in wei
    gas_fee: uint256 = gas_fee_amount * tx.gasprice
    _compass: address = self.compass
    self.compass_check(_compass)
    _rewards_security_balance: uint256 = self.rewards_security_balance
    if _rewards_security_balance >= gas_fee:
        self.rewards_security_balance = unsafe_sub(_rewards_security_balance, gas_fee)
        self.claimable_rewards[sender] = unsafe_add(self.claimable_rewards[sender], gas_fee)
        self.total_claims = unsafe_add(self.total_claims, gas_fee)
        log ReserveSecurityFee(sender, gas_fee_amount)

@external
def bridge_community_fee_to_paloma(amount: uint256, dex: address, payload: Bytes[1028], min_grain: uint256) -> uint256:
    # bridge community fee t0 paloma address
    # amount: community fee ETH amount
    # dex: address of the DEX to use for exchanging the token
    # payload: the function payload to exchange ETH to grain for the dex
    # min_grain: expected grain amount getting from dex to prevent front-running(high slippage / sandwich attack)
    _compass: address = self.compass
    self.compass_check(_compass)
    _grain: address = self.grain
    _rewards_community_balance: uint256 = self.rewards_community_balance
    assert _rewards_community_balance >= amount, "Insufficient community fee"
    self.rewards_community_balance = unsafe_sub(_rewards_community_balance, amount)
    grain_balance: uint256 = self.swap_grain(_grain, amount, dex, payload, min_grain)
    ERC20(_grain).transfer(_compass, grain_balance)
    log BridgeCommunityFeeToPaloma(grain_balance)
    return grain_balance

@external
def update_compass(_new_compass: address):
    # update compass address
    # _new_compass: new compass address
    self.compass_check(self.compass)
    self.compass = _new_compass
    log UpdateCompass(_new_compass)

@external
def initialize_compass(_compass: address):
    assert DEPLOYER == msg.sender and self.compass == empty(address)
    self.compass = _compass
    log InitializeCompass(_compass)

@external
def initialize_grain(_compass: address, _grain: address):
    assert DEPLOYER == msg.sender and self.grain == empty(address)
    self.grain = _grain
    log InitializeGrain(_grain)