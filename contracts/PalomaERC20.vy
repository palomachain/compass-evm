#pragma version 0.3.10
#pragma optimize gas
#pragma evm-version shanghai

"""
@title PalomaERC20
@license Apache 2.0
@author Volume.Finance
@notice v1.3.0
"""

interface CompassAddressProvider:
    def compass() -> address: view

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

COMPASS_ADDRESS_PROVIDER: public(immutable(CompassAddressProvider))
name: public(String[64])
symbol: public(String[32])
decimals: public(uint8)
totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])

@external
def __init__(compass_address_provider: address, _name: String[64], _symbol: String[32], _decimals: uint8):
    COMPASS_ADDRESS_PROVIDER = CompassAddressProvider(compass_address_provider)
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals

@external
def transfer(_to: address, _value: uint256) -> bool:
    assert _to != empty(address), "Zero address"
    compass: address = COMPASS_ADDRESS_PROVIDER.compass()
    if msg.sender == compass:
        assert not Compass(msg.sender).slc_switch(), "SLC is not available"
    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] = unsafe_add(self.balanceOf[_to], _value)
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from: address, _to: address, _value: uint256) -> bool:
    assert _to != empty(address), "Zero address"
    compass: address = COMPASS_ADDRESS_PROVIDER.compass()
    if msg.sender == compass:
        assert not Compass(msg.sender).slc_switch(), "SLC is not available"
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] = unsafe_add(self.balanceOf[_to], _value)
    self.allowance[_from][msg.sender] -= _value
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender: address, _value: uint256) -> bool:
    assert _value == 0 or (self.allowance[msg.sender][_spender] == 0 and msg.sender != COMPASS_ADDRESS_PROVIDER.compass()), "Not available"
    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@external
def mint(_to: address, _value: uint256):
    assert msg.sender == COMPASS_ADDRESS_PROVIDER.compass(), "Not Compass"
    assert not Compass(msg.sender).slc_switch(), "SLC is unavailable"
    self.totalSupply += _value
    self.balanceOf[_to] = unsafe_add(self.balanceOf[_to], _value)
    log Transfer(empty(address), _to, _value)

@external
def burnFrom(_from: address, _value: uint256):
    compass: address = COMPASS_ADDRESS_PROVIDER.compass()
    if msg.sender == compass:
        assert not Compass(msg.sender).slc_switch(), "SLC is not available"
    self.allowance[_from][msg.sender] -= _value
    self.balanceOf[_from] -= _value
    self.totalSupply -= _value
    log Transfer(_from, empty(address), _value)

@external
def burn(_value: uint256):
    self.balanceOf[msg.sender] -= _value
    self.totalSupply -= _value
    log Transfer(msg.sender, empty(address), _value)

@external
def increaseAllowance(_spender: address, _value: uint256) -> bool:
    compass: address = COMPASS_ADDRESS_PROVIDER.compass()
    assert compass != msg.sender, "Not available"
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
