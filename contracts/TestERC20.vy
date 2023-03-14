# @version 0.3.7

event Transfer:
    _from: indexed(address)
    _to: indexed(address)
    _value: uint256

event Approval:
    _owner: indexed(address)
    _spender: indexed(address)
    _value: uint256

name: public(String[64])
symbol: public(String[32])

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
totalSupply: public(uint256)

@external
def __init__(_name: String[64], _symbol: String[32], init_supply: uint256):
    self.name = _name
    self.symbol = _symbol
    self.balanceOf[msg.sender] = init_supply
    self.totalSupply = init_supply
    log Transfer(ZERO_ADDRESS, msg.sender, init_supply)

@external
@pure
def decimals() -> uint8:
    return 18


@external
def transfer(_to : address, _value : uint256) -> bool:
    assert _to != ZERO_ADDRESS # dev: zero address
    self.balanceOf[msg.sender] -= _value
    self.balanceOf[_to] += _value
    log Transfer(msg.sender, _to, _value)
    return True

@external
def transferFrom(_from : address, _to : address, _value : uint256) -> bool:
    assert _to != ZERO_ADDRESS # dev: zero address
    self.balanceOf[_from] -= _value
    self.balanceOf[_to] += _value
    self.allowance[_from][msg.sender] -= _value
    log Transfer(_from, _to, _value)
    return True

@external
def approve(_spender : address, _value : uint256) -> bool:
    assert _value == 0 or self.allowance[msg.sender][_spender] == 0
    self.allowance[msg.sender][_spender] = _value
    log Approval(msg.sender, _spender, _value)
    return True

@external
def increaseAllowance(_spender: address, _value: uint256) -> bool:
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
