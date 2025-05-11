// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract MockTSwapPool {
    uint256 public price = 1e18;

    event PriceUpdated(uint256 newPrice);

    function getPriceOfOnePoolTokenInWeth() external view returns (uint256) {
        return price;
    }

    function set_price_mock_mainpulation(uint256 _price) external {
        price = _price;
        emit PriceUpdated(_price);
    }
}
