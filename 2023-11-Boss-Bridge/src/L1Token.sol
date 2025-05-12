// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract L1Token is ERC20 {
    uint256 private constant INITIAL_SUPPLY = 1_000_000;

    constructor() ERC20("BossBridgeToken", "BBT") {
        // @audit: 如果使用TokenFactory部署该代币，那么初始流动性将全部被锁定，因为TokenFactory没有相关操作的函数
        _mint(msg.sender, INITIAL_SUPPLY * 10 ** decimals());
    }
}
