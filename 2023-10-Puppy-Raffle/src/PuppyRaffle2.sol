// SPDX-License-Identifier: MIT
// @audit: 合约编译的版本最好为指定版本
// @fixed: 使用确定的solidity版本
pragma solidity 0.8.0;

import "forge-std/console.sol";

// @notice:在引入外部库时，需要检查该版本是否安全
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Base64} from "lib/base64/base64.sol";

contract PuppyRaffle2 is ERC721, Ownable {
    using Address for address payable;

    uint256 public immutable entranceFee;

    address[] public players;
    // @audit:该变量可以使用immutable修饰符进行优化
    // @fixed: 使用immutable修饰符进行优化
    uint256 public immutable raffleDuration;

    uint256 public raffleStartTime;
    address public previousWinner;

    // We do some storage packing to save gas
    address public feeAddress;
    // @audit:该变量的类型应该为uint256
    // @fixed: 将该变量的类型修改为uint256
    uint256 public totalFees = 0;

    // mappings to keep track of token traits
    mapping(uint256 => uint256) public tokenIdToRarity;

    mapping(uint256 => string) public rarityToUri;
    mapping(uint256 => string) public rarityToName;

    // Stats for the common puppy (pug)
    string private commonImageUri = "ipfs://QmSsYRx3LpDAb1GZQm7zZ1AuHZjfbPkD6J7s9r41xu1mf8";
    uint256 public constant COMMON_RARITY = 70;
    string private constant COMMON = "common";

    // Stats for the rare puppy (st. bernard)
    string private rareImageUri = "ipfs://QmUPjADFGEKmfohdTaNcWhp7VGk26h5jXDA7v3VtTnTLcW";
    uint256 public constant RARE_RARITY = 25;
    string private constant RARE = "rare";

    // Stats for the legendary puppy (shiba inu)
    string private legendaryImageUri = "ipfs://QmYx6GsYAKnNzZ9A6NvEKV9nf1VaDzJrqDR23Y8YSkebLU";
    uint256 public constant LEGENDARY_RARITY = 5;
    string private constant LEGENDARY = "legendary";

    // @fixed: 增添一个mapping，记录每个players对应的index
    mapping(address => uint256) public playerToIndex;

    // @fixed: 避免使用magic number
    uint256 public constant PRIZE_POOL_PERCENTAGE = 80;
    uint256 public constant FEE_PERCENTAGE = 20;

    // Events
    event RaffleEnter(address[] newPlayers);
    event RaffleRefunded(address player);
    event FeeAddressChanged(address newFeeAddress);
    // @fixed: 增添一个event，记录selectWinner的结果
    event WinnerSelected(address winner, uint256 tokenId, uint256 rarity);
    // @fixed: 增添一个event，记录withdrawFees的结果
    event FeesWithdrawn(address feeAddress, uint256 amount);

    /// @param _entranceFee the cost in wei to enter the raffle
    /// @param _feeAddress the address to send the fees to
    /// @param _raffleDuration the duration in seconds of the raffle
    constructor(uint256 _entranceFee, address _feeAddress, uint256 _raffleDuration) ERC721("Puppy Raffle", "PR") {
        // @audit:应该对_entranceFee进行限制
        // 在enterRaffle函数中，由于要校验msg.value == entranceFee * newPlayers.length，此时若_entranceFee过大
        // 则导致整数溢出，从而导致该条件无法通过

        // @fixed: 对_entranceFee进行限制
        require(
            _entranceFee > 0 && _entranceFee <= 10 ether,
            "PuppyRaffle: Entrance fee must be greater than 0 and less than 10 ether"
        );
        entranceFee = _entranceFee;

        feeAddress = _feeAddress;
        raffleDuration = _raffleDuration;
        raffleStartTime = block.timestamp;

        rarityToUri[COMMON_RARITY] = commonImageUri;
        rarityToUri[RARE_RARITY] = rareImageUri;
        rarityToUri[LEGENDARY_RARITY] = legendaryImageUri;

        rarityToName[COMMON_RARITY] = COMMON;
        rarityToName[RARE_RARITY] = RARE;
        rarityToName[LEGENDARY_RARITY] = LEGENDARY;
    }

    /// @notice this is how players enter the raffle
    /// @notice they have to pay the entrance fee * the number of players
    /// @notice duplicate entrants are not allowed
    /// @param newPlayers the list of players to enter the raffle
    function enterRaffle(address[] memory newPlayers) public payable {
        // @fixed: 确保players数组不为空，从而避免发出无效事件
        require(newPlayers.length > 0, "PuppyRaffle: Must enter at least one player");

        require(msg.value == entranceFee * newPlayers.length, "PuppyRaffle: Must send enough to enter raffle");

        for (uint256 i = 0; i < newPlayers.length; i++) {
            // @fixed: 在每次插入时直接检查重复性
            require(playerToIndex[newPlayers[i]] == 0, "Player already entered");

            // @fixed: 确保新玩家不是合约，从而避免玩家无法接收eth而卡住合约
            // todo 然而，这种方式依然可以被绕过，因为合约在constructor中，其extcodesize为0
            require(!Address.isContract(newPlayers[i]), "PuppyRaffle: Player cannot be a contract");

            players.push(newPlayers[i]);
        }

        // Check for duplicates
        // @audit 由于多次for循环，因此导致gas消耗过高，可能导致dos攻击
        // @fixed: 删除该代码
        // for (uint256 i = 0; i < players.length - 1; i++) {
        //     for (uint256 j = i + 1; j < players.length; j++) {
        //         require(players[i] != players[j], "PuppyRaffle: Duplicate player");
        //     }
        // }
        // @audit:当newPlayers长度为0时，依然会触发该事件
        emit RaffleEnter(newPlayers);
    }

    /// @param playerIndex the index of the player to refund. You can find it externally by calling `getActivePlayerIndex`
    /// @dev This function will allow there to be blank spots in the array
    function refund(uint256 playerIndex) public {
        // @fixed: 确保refund只能在开奖后进行，从而防止抢跑
        // @fixed: 通过确保退款在开奖之后进行，使得address(0)不会被选为赢家，因此selectWinner函数不会revert
        require(block.timestamp > raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");

        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "PuppyRaffle: Only the player can refund");
        // @audit: 该条件多余，因为msg.sender不可能为address(0)
        // @fixed: 删除该条件
        // require(playerAddress != address(0), "PuppyRaffle: Player already refunded, or is not active");

        // @audit: 可以使用 delete players[playerIndex]，而不需要将其设置为address(0)
        // @fixed: 使用 delete players[playerIndex]
        delete players[playerIndex];

        // @audit: 在退款时，并没有将totalFees进行更新，这导致即使用户退款了，但是totalFees依然记录了该用户的费用
        // @fixed: 在退款时，将totalFees进行更新
        totalFees = totalFees - entranceFee;

        // @audit：重入攻击
        // @fixed: 确保在退款前，先将该用户从players中删除
        payable(msg.sender).sendValue(entranceFee);

        emit RaffleRefunded(playerAddress);
    }

    /// @notice a way to get the index in the array
    /// @param player the address of a player in the raffle
    /// @return the index of the player in the array, if they are not active, it returns 0
    function getActivePlayerIndex(address player) external view returns (uint256) {
        // @audit
        // 此处，会在找不到player时返回0，但当player在index 0时还是返回0
        // 那么真正的player就无法判断自己是否在activePlayers中
        // @fixed: 注释该代码
        // for (uint256 i = 0; i < players.length; i++) {
        //     if (players[i] == player) {
        //         return i;
        //     }
        // }
        // return 0;

        // @fixed: 直接使用mapping进行查询
        if (playerToIndex[player] != 0) {
            return playerToIndex[player];
        } else {
            return type(uint256).max;
        }
    }

    /// @notice this function will select a winner and mint a puppy
    /// @notice there must be at least 4 players, and the duration has occurred
    /// @notice the previous winner is stored in the previousWinner variable
    /// @dev we use a hash of on-chain data to generate the random numbers
    /// @dev we reset the active players array after the winner is selected
    /// @dev we send 80% of the funds to the winner, the other 20% goes to the feeAddress
    function selectWinner() external {
        // @audit: 错误的比较
        // 该条件应该为block.timestamp > raffleStartTime + raffleDuration
        // 因为有可能在block.timestamp = raffleStartTime + raffleDuration的情况下，抽奖依然在进行

        // @fixed: 修改为block.timestamp > raffleStartTime + raffleDuration
        require(block.timestamp > raffleStartTime + raffleDuration, "PuppyRaffle: Raffle not over");

        require(players.length >= 4, "PuppyRaffle: Need at least 4 players");

        // @audit：使用伪随机数
        // @audit：如果选择到的winner刚好已经退款，那么会导致奖励发送到0地址
        // @audit：由于该函数公开，则可以监听该函数的执行，如果没有获奖，则在该函数执行前插入一笔refund，从而规避风险
        uint256 winnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;

        address winner = players[winnerIndex];
        uint256 totalAmountCollected = players.length * entranceFee;

        // @audit：使用了magic number
        // @fixed: 使用常量替代magic number
        uint256 prizePool = (totalAmountCollected * PRIZE_POOL_PERCENTAGE) / 100;
        // @audit：这种写法有出现精度损失的可能，但对于可以被100整除的数字不会有问题
        // @fixed: 使用total - prize_pool，保证fee不会缺少记录
        uint256 fee = totalAmountCollected - prizePool;

        // @audit 整数溢出
        // solidity 0.8.0之前，可能导致整数溢出，从而使得totalFees环回

        // @audit 不安全的值类型转换 uint256 -> uint64
        // uint64.max = 18446744073709551615
        // 当有100个用户进行抽奖时，fee为 20000000000000000000
        // 此时，fee被转换为uint64时，fee = 18446744073709551615，这意味着一部分的fee被丢失

        // @fixed: 使用uint256进行存储
        totalFees = totalFees + fee;

        uint256 tokenId = totalSupply();

        // We use a different RNG calculate from the winnerIndex to determine rarity
        // @audit：稀有度可被预测
        // 当我们是胜者时，我们可以一直进行selectWinner，直到我们获得想要的稀有度

        // todo @fixed: 使用chainlink VRF进行随机数生成
        uint256 rarity = uint256(keccak256(abi.encodePacked(msg.sender, block.difficulty))) % 100;

        // @audit：概率对应错误
        // 对于COMMON_RARITY，这意味着70%的概率，然而[0,70]代表的是71个数字，因此概率为71%

        // @fixed: 修改<=为<
        if (rarity < COMMON_RARITY) {
            tokenIdToRarity[tokenId] = COMMON_RARITY;
        } else if (rarity < COMMON_RARITY + RARE_RARITY) {
            tokenIdToRarity[tokenId] = RARE_RARITY;
        } else {
            tokenIdToRarity[tokenId] = LEGENDARY_RARITY;
        }

        delete players;
        raffleStartTime = block.timestamp;
        previousWinner = winner;
        (bool success,) = winner.call{value: prizePool}("");
        // @audit：一旦胜者无法接收eth，则会导致合约无法继续
        // @fixed: 确保玩家都不是合约
        require(success, "PuppyRaffle: Failed to send prize pool to winner");
        _safeMint(winner, tokenId);
        // @audit:缺少event释放
        emit WinnerSelected(winner, tokenId, tokenIdToRarity[tokenId]);
    }

    /// @notice this function will withdraw the fees to the feeAddress
    function withdrawFees() external {
        // @audit：过于严格的条件
        // 正常情况下，该条件是可以被通过的，因为本合约没有fallback和receive函数，这意味着该合约无法接收eth，进而无法操纵address(this).balance
        // 然而，如果是某个合约进行selfdestruct，并且指定了该合约为接收地址，那么该合约依然能接收到eth，导致该条件无法通过

        // @fixed: 注释掉
        // require(address(this).balance == uint256(totalFees), "PuppyRaffle: There are currently players active!");
        uint256 feesToWithdraw = totalFees;
        totalFees = 0;
        (bool success,) = feeAddress.call{value: feesToWithdraw}("");
        require(success, "PuppyRaffle: Failed to withdraw fees");
        // @audit:缺少event释放
        emit FeesWithdrawn(feeAddress, feesToWithdraw);
    }

    /// @notice only the owner of the contract can change the feeAddress
    /// @param newFeeAddress the new address to send fees to
    function changeFeeAddress(address newFeeAddress) external onlyOwner {
        feeAddress = newFeeAddress;
        emit FeeAddressChanged(newFeeAddress);
    }

    /// @notice this function will return true if the msg.sender is an active player
    //  @audit:这个函数未使用
    function _isActivePlayer() internal view returns (bool) {
        // @fixed: 使用mapping进行查询
        // for (uint256 i = 0; i < players.length; i++) {
        //     if (players[i] == msg.sender) {
        //         return true;
        //     }
        // }
        // return false;
        return playerToIndex[msg.sender] != 0;
    }

    /// @notice this could be a constant variable
    function _baseURI() internal pure returns (string memory) {
        return "data:application/json;base64,";
    }

    /// @notice this function will return the URI for the token
    /// @param tokenId the Id of the NFT
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "PuppyRaffle: URI query for nonexistent token");

        uint256 rarity = tokenIdToRarity[tokenId];
        string memory imageURI = rarityToUri[rarity];
        string memory rareName = rarityToName[rarity];

        return string(
            abi.encodePacked(
                _baseURI(),
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"',
                            name(),
                            '", "description":"An adorable puppy!", ',
                            '"attributes": [{"trait_type": "rarity", "value": ',
                            rareName,
                            '}], "image":"',
                            imageURI,
                            '"}'
                        )
                    )
                )
            )
        );
    }
}
