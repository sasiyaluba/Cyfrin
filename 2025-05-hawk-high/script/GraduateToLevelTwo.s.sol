// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {LevelTwo} from "../src/LevelTwo.sol";
import {LevelOne} from "../src/LevelOne.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract GraduateToLevelTwo is Script {
    address public levelOneProxyAddress;

    function setUp() public {
        levelOneProxyAddress = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);
    }

    function deployLevelTwo() public returns (LevelTwo) {
        vm.startBroadcast();
        LevelTwo levelTwo = new LevelTwo();
        vm.stopBroadcast();

        return levelTwo;
    }

    function run() external returns (address levelTwoImplementationAddress) {
        vm.startBroadcast();
        LevelTwo levelTwo = new LevelTwo();
        vm.stopBroadcast();

        levelTwoImplementationAddress = address(levelTwo);

        LevelOne levelOneProxy = LevelOne(levelOneProxyAddress);

        bytes memory data = abi.encodeCall(LevelTwo.graduate, ());

        vm.startBroadcast();
        levelOneProxy.graduateAndUpgrade(levelTwoImplementationAddress, data);
        vm.stopBroadcast();

        return levelTwoImplementationAddress;
    }
}
