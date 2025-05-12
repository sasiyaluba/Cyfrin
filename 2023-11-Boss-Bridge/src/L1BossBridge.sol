// __| |_____________________________________________________| |__
// __   _____________________________________________________   __
//   | |                                                     | |
//   | | ____                  ____       _     _            | |
//   | || __ )  ___  ___ ___  | __ ) _ __(_) __| | __ _  ___ | |
//   | ||  _ \ / _ \/ __/ __| |  _ \| '__| |/ _` |/ _` |/ _ \| |
//   | || |_) | (_) \__ \__ \ | |_) | |  | | (_| | (_| |  __/| |
//   | ||____/ \___/|___/___/ |____/|_|  |_|\__,_|\__, |\___|| |
//   | |                                          |___/      | |
// __| |_____________________________________________________| |__
// __   _____________________________________________________   __
//   | |                                                     | |

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { L1Vault } from "./L1Vault.sol";

contract L1BossBridge is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public DEPOSIT_LIMIT = 100_000 ether;

    IERC20 public immutable token;
    L1Vault public immutable vault;
    mapping(address account => bool isSigner) public signers;

    error L1BossBridge__DepositLimitReached();
    error L1BossBridge__Unauthorized();
    error L1BossBridge__CallFailed();

    event Deposit(address from, address to, uint256 amount);

    constructor(IERC20 _token) Ownable(msg.sender) {
        token = _token;
        vault = new L1Vault(token);
        // Allows the bridge to move tokens out of the vault to facilitate withdrawals
        vault.approveTo(address(this), type(uint256).max);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setSigner(address account, bool enabled) external onlyOwner {
        signers[account] = enabled;
    }

    /*
     * @notice Locks tokens in the vault and emits a Deposit event
     * the unlock event will trigger the L2 minting process. There are nodes listening
     * for this event and will mint the corresponding tokens on L2. This is a centralized process.
     * 
     * @param from The address of the user who is depositing tokens
     * @param l2Recipient The address of the user who will receive the tokens on L2
     * @param amount The amount of tokens to deposit
     */

    // @audit: 缺少重入保护
    function depositTokensToL2(address from, address l2Recipient, uint256 amount) external whenNotPaused {
        /**
         * @audit: 使用from容易被攻击
         *
         * 由于在执行`depositTokensToL2`进行deposit之前，需要先执行`approve`
         * 那么攻击者可以监听交易，一旦监听到某个用户授权当前项目，执行`depositTokensToL2`并传入l2Recipient参数为攻击者自身的地址
         * 从而导致用户的资金损失
         */

        /**
         * @audit: 此处利用balance来校验是否超过了deposit限制，攻击者可以通过向vault中转账使得deposit限制被错误开启
         */
        if (token.balanceOf(address(vault)) + amount > DEPOSIT_LIMIT) {
            revert L1BossBridge__DepositLimitReached();
        }

        // @audit: 此处应检查safeTransferFrom的返回值
        token.safeTransferFrom(from, address(vault), amount);

        // Our off-chain service picks up this event and mints the corresponding tokens on L2
        emit Deposit(from, l2Recipient, amount);
    }

    /*
     * @notice This is the function responsible for withdrawing tokens from L2 to L1.
     * Our L2 will have a similar mechanism for withdrawing tokens from L1 to L2.
     * @notice The signature is required to prevent replay attacks. 
     * 
     * @param to The address of the user who will receive the tokens on L1
     * @param amount The amount of tokens to withdraw
     * @param v The v value of the signature
     * @param r The r value of the signature
     * @param s The s value of the signature
     */

    function withdrawTokensToL1(address to, uint256 amount, uint8 v, bytes32 r, bytes32 s) external {
        /**
         * @audit: 此处进行验证缺少nonce，因此该签名可以被重用
         */

        /**
         * @audit: 此处未校验用户是否真正存入了amount数量的token，攻击者可以存入小额token，但提取大量token
         */
        sendToL1(
            v,
            r,
            s,
            abi.encode(
                address(token),
                0, // value
                abi.encodeCall(IERC20.transferFrom, (address(vault), to, amount))
            )
        );
    }

    /*
     * @notice This is the function responsible for withdrawing ETH from L2 to L1.
     *
     * @param v The v value of the signature
     * @param r The r value of the signature
     * @param s The s value of the signature
     * @param message The message/data to be sent to L1 (can be blank)
     */
    function sendToL1(uint8 v, bytes32 r, bytes32 s, bytes memory message) public nonReentrant whenNotPaused {
        /**
         * @audit:public修饰符使得该函数可被任意调用
         * 此处若signer作恶，因此signer可以构造任意的message，执行任意的函数
         */
        address signer = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(keccak256(message)), v, r, s);

        if (!signers[signer]) {
            revert L1BossBridge__Unauthorized();
        }

        (address target, uint256 value, bytes memory data) = abi.decode(message, (address, uint256, bytes));

        (bool success,) = target.call{ value: value }(data);
        if (!success) {
            revert L1BossBridge__CallFailed();
        }
    }
}
