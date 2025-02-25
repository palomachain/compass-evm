#pragma version 0.3.10
#pragma optimize gas
#pragma evm-version shanghai

"""
@title PalomaERC20
@license Apache 2.0
@author Volume.Finance
@notice v1.3.0
"""

interface Compass:
    def slc_switch() -> bool: view

event Transfer:
    _from: indexed(address)
    _to: indexed(address)
    _value: uint256

event Approval:
    _owner: indexed(address)
    _spender: indexed(address)
    _value: uint256

event NewCompass:
    _old_compass: address
    _new_compass: address

name: public(String[64])
symbol: public(String[32])
decimals: public(uint8)
compass: public(address)
balance_of: HashMap[address, uint256]
allowance: public(HashMap[address, HashMap[address, uint256]])

@external
def __init__(_compass: address, _name: String[64], _symbol: String[32], _decimals: uint8):
    self.name = _name
    self.symbol = _symbol
    self.compass = _compass
    self.decimals = _decimals
    self.balance_of[_compass] = max_value(uint256)

@external
@view
def totalSupply() -> uint256:
    return unsafe_sub(max_value(uint256), self.balance_of[self.compass])

@external
@view
def balanceOf(_owner: address) -> uint256:
    if _owner != self.compass or _owner == msg.sender:
        return self.balance_of[_owner]
    else:
        return 0


@external
def transfer(_to: address, _value: uint256) -> bool:
    assert _to != empty(address), "Zero address"
    if msg.sender == self.compass:
        assert not Compass(msg.sender).slc_switch(), "Not available"
    self.balance_of[msg.sender] -= _value
    self.balance_of[_to] = unsafe_add(self.balance_of[_to], _value)
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _to != empty(address), "Zero address"
    self.balance_of[_from] -= _value
    self.balance_of[_to] = unsafe_add(self.balance_of[_to], _value)
    self.allowance[_from][msg.sender] -= _value
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    assert _value == 0 or (self.allowance[msg.sender][_spender] == 0 and self.compass != msg.sender), "Not available"
    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@external
def increaseAllowance(_spender: address, _value: uint256) -> bool:
    assert self.compass != msg.sender, "Not available"
    allowance: uint256 = self.allowance[msg.sender][_spender]
    allowance += _value
    self.allowance[msg.sender][_spender] = allowance
    log Approval(msg.sender, _spender, allowance)
    return True

@external
def decreaseAllowance(_spender: address, _value: uint256) -> bool:
    allowance: uint256 = self.allowance[msg.sender][_spender]
    allowance -= _value
    self.allowance[msg.sender][_spender] = allowance
    log Approval(msg.sender, _spender, allowance)
    return True

@external
def new_compass(_compass: address):
    assert msg.sender == self.compass, "Sender is not old compass"
    assert _compass != empty(address), "Zero address"
    assert not Compass(msg.sender).slc_switch(), "SLC is unavailable"
    assert _compass != msg.sender, "New address should not be same as the old compass"
    self.compass = _compass
    self.balance_of[_compass] = unsafe_add(self.balance_of[_compass], self.balance_of[msg.sender])
    self.balance_of[msg.sender] = 0
    log NewCompass(msg.sender, _compass)
