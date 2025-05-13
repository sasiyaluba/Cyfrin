// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {LevelOne} from "../src/LevelOne.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockUSDC} from "../test/mocks/MockUSDC.sol";

contract DeployLevelOne is Script {
    address public principal = makeAddr("principal");
    uint256 public schoolFees = 5_000e18; // 5k usdc
    MockUSDC usdc;
    LevelOne public levelOneImplementation;
    ERC1967Proxy public proxy;

    function run() external returns (address proxyAddress) {
        proxyAddress = deployLevelOne();
        return proxyAddress;
    }

    function deployLevelOne() public returns (address) {
        usdc = new MockUSDC();

        vm.startBroadcast();
        levelOneImplementation = new LevelOne();
        proxy = new ERC1967Proxy(address(levelOneImplementation), "");
        LevelOne(address(proxy)).initialize(principal, schoolFees, address(usdc));
        vm.stopBroadcast();

        return address(proxy);
    }

    function getProxyAddress() external view returns (address) {
        return address(proxy);
    }

    function getImplementationAddress() external view returns (address) {
        return address(levelOneImplementation);
    }

    function getUSDC() external view returns (MockUSDC) {
        return usdc;
    }

    function getPrincipal() public view returns (address) {
        return principal;
    }

    function getSchoolFees() public view returns (uint256) {
        return schoolFees;
    }
}
