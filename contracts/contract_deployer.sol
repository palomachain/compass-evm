// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

contract DeployBytecode {
    function deployFromBytecode(bytes memory bytecode) public returns (address) {
        address child;
        assembly{
            mstore(0x0, bytecode)
            child := create(0,0xa0, calldatasize())
        }
        return child;
   }
}