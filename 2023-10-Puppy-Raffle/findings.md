### [M-#] `PuppyRaffle::enterRaffle()`在代码中遍历数组以检查重复性，这是一种潜在的 dos 攻击，因为递增的 gas 费用使得后续用户进行交易时需要支付更高的 gas 费用。

**IMPACT:** 用户参与抽奖时需要支付更高的 gas 费用，可能导致用户无法参与。

**Description:** `PuppyRaffle::enterRaffle()`在代码中通过双重遍历数组来检查重复性，这使得攻击者可以通过向数组中添加大量元素来增加 gas 费用，从而导致后续用户在进行交易时需要支付更高的 gas 费用。

**POC:**

当 100 名用户参加时，101 位用户参加时消耗 gas 为 6503272
当 1000 名用户参加时，1001 位用户参加时消耗 gas 为 440181896

```solidity
    function test_dos() public {
        uint256 players_length = 100;
        address[] memory players = new address[](players_length);
        for (uint256 i = 0; i < players_length; i++) {
            players[i] = address(i);
        }

        uint256 gas_start = gasleft();
        puppyRaffle.enterRaffle{value: entranceFee * players_length}(players);
        uint256 gas_end = gasleft();
        uint256 gas_used = gas_start - gas_end;
        console.log("Gas used for entering 1000 players: ", gas_used);
    }
```

**Mitigation:**

对于重复性检查的情况，一般使用 mapping 结合数组来进行检查。

```solidity
    mapping (address => uint256) public addressToIndex;
    for (uint256 i = 0; i < newPlayers.length; i++) {
            require(addressToIndex[newPlayers[i]] == 0, "Player already entered");
            players.push(newPlayers[i]);
        }
```

### [S-#] `PuppyRaffle::refund()`在代码由于先转账，后更新状态变量，可能导致重入攻击。

**IMPACT:** 攻击者可以通过重入攻击来获取不当利益。

**Description:** `PuppyRaffle::refund()`中，首先进行`payable(msg.sender).sendValue(entranceFee);`转账操作，然后更新状态变量`players[playerIndex] = address(0);`，由于转账操作会触发 msg.sender 的 fallback 函数，如果在 fallback 函数中回调`PuppyRaffle::refund()`，依然可以通过取款的前置判断条件，从而引入重入攻击。

**POC:**

```solidity
    function test_reen() public {
        // 100个用户参加
        uint256 players_length = 100;
        address[] memory players = new address[](players_length);
        for (uint256 i = 0; i < players_length; i++) {
            players[i] = address(i);
        }

        puppyRaffle.enterRaffle{value: entranceFee * players_length}(players);

        // 重入

        ReentrancyAttack attack = new ReentrancyAttack(address(puppyRaffle));
        vm.deal(address(attack), entranceFee);
        vm.startPrank(address(attack));
        attack.attack{value: entranceFee}();
        assertEq(address(attack).balance, entranceFee * 101);
        vm.stopPrank();
    }
```

**Mitigation:**

使用`checks-effects-interactions`模式。

```solidity
    function refund(uint256 playerIndex) public {
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");
        players[playerIndex] = address(0);
        payable(msg.sender).sendValue(entranceFee);
        emit RaffleRefunded(playerAddress);
    }
```

### [S-#] `PuppyRaffle::selectWinner()`中 winnerIndex 和 rarity 均使用了伪随机数。

**IMPACT:** 伪随机数可能导致攻击者可以通过操纵随机数来选择中奖者。同时稀有度也可以被一定程度的操纵。

**Description:** `PuppyRaffle::selectWinner()`中，winnerIndex 和 rarity 均使用了伪随机数，这可能导致攻击者可以通过操纵随机数来选择中奖者。同时稀有度也可以被一定程度的操纵。

**Mitigation:**

使用 Chainlink VRF 来生成随机数。

### [S-#] `PuppyRaffle::selectWinner()`中存在整数溢出问题。

**IMPACT:** 随着用户数量的增多，totalFees 逐渐无法被 uint64 类型的变量存储，导致整数溢出。

**Description:** `PuppyRaffle::selectWinner()`中，totalFees 使用了 uint64 类型的变量来存储，其计算公式为`totalFees = totalFees + uint64(fee)`，然而 fee 本身就是一个 uint64 类型的变量，因此随着用户数量的增多，totalFees 逐渐无法被 uint64 类型的变量存储，导致整数溢出。

**Mitigation:**

1. 使用 uint256 类型的变量来存储 totalFees。
2. 使用 0.8.0 以上版本的 Solidity 来进行整数溢出检查。

### [S-#] `PuppyRaffle::selectWinner()`中不安全映射问题

**IMPACT:** `PuppyRaffle::selectWinner()`中 fee 本身为 uint256 类型，然而在计算时使用了 uint64 类型的变量来存储，这可能导致 fee 的数值被损失。

**Description:** `PuppyRaffle::selectWinner()`中 fee 本身为 uint256 类型，然而在计算时使用了 uint64 类型的变量来存储，solidity 中整数进行类型转换时会截断高位，因此 fee 的数值会被损失。
