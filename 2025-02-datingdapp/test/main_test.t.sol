// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SoulboundProfileNFT.sol";
import "../src/LikeRegistry.sol";
import "../src/MultiSig.sol";

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MainTest is Test {
    SoulboundProfileNFT public profileNFT;
    LikeRegistry public likeRegistry;

    address public registryOwner = makeAddr("registryOwner");
    address public profileNFTOwner = makeAddr("profileNFTOwner");

    CommonUser public alice = new CommonUser();
    CommonUser public bob = new CommonUser();
    CommonUser public john = new CommonUser();
    CommonUser public eva = new CommonUser();

    function setUp() public {
        // 创建nft
        vm.prank(profileNFTOwner);
        profileNFT = new SoulboundProfileNFT();
        vm.label(address(profileNFT), "SoulboundProfileNFT");
        // 创建registry
        vm.prank(registryOwner);
        likeRegistry = new LikeRegistry(address(profileNFT));
        vm.label(address(likeRegistry), "LikeRegistry");

        _setup_user(address(alice), 18, "Alice");
        _setup_user(address(bob), 20, "Bob");
        _setup_user(address(john), 22, "John");
        _setup_user(address(eva), 25, "Eva");
    }

    // 有两个问题 LikeRegistry.sol
    // 1. 代码中，没有更新userBalances，因此多签钱包的余额为0
    // 2. 当用户互相匹配创建了多签钱包之后，用户并不知道多签钱包的地址
    function test_no_update_user_balances() public {
        vm.prank(address(alice));
        likeRegistry.likeUser{value: 1 ether}(address(bob));

        vm.prank(address(bob));
        likeRegistry.likeUser{value: 1 ether}(address(alice));

        address multiSigWallet = address(MultiSigWallet(payable(0x811f3949ce4C400E1e32D222DB6698A554cb15cA)));

        assertEq(address(multiSigWallet).balance, 0, "userBalances should not be updated");
    }

    function _setup_user(address user, uint8 age, string memory name) internal {
        vm.deal(user, 1 ether);
        vm.prank(user);
        profileNFT.mintProfile("User", age, string.concat("ipfs://", name));
        vm.label(user, name);
    }
}

contract CommonUser is IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        override
        returns (bytes4)
    {
        return this.onERC721Received.selector;
    }
}
