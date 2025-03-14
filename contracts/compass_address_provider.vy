# pragma version 0.4.1
# pragma optimize gas
# pragma evm-version cancun

"""
@title Compass Address Provider
@license Apache 2.0
@author Volume.Finance
@notice v1.0.0
"""
interface Compass:
    def slc_switch() -> bool: view

compass: public(address)
grain: public(address)

event CompassUpdated:
    _old_compass: address
    _new_compass: address

event GrainUpdated:
    _old_grain: address
    _new_grain: address

@deploy
def __init__(_compass: address):
    self.compass = _compass

@external
def update_compass(_new_compass: address):
    assert not staticcall Compass(msg.sender).slc_switch(), "SLC is not available"
    assert msg.sender == self.compass
    self.compass = _new_compass
    log CompassUpdated(_old_compass=msg.sender, _new_compass=_new_compass)

@external
def update_grain(_new_grain: address):
    assert not staticcall Compass(msg.sender).slc_switch(), "SLC is not available"
    assert msg.sender == self.compass
    _old_grain: address = self.grain
    self.grain = _new_grain
    log GrainUpdated(_old_grain, _new_grain)
    

