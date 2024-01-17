// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { console, Test } from "forge-std/Test.sol";
import "test/utils/Constants.sol";

import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */
contract UsdnProtocolHandler is UsdnProtocol, Test {
    uint128 public constant wstethInitialPrice = 2630 ether;
    uint256 public immutable initialBlock;
    uint256[] public prevActionBlock;

    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing)
        UsdnProtocol(usdn, asset, oracleMiddleware, tickSpacing)
    {
        // createAndFundUser(address(asset), 10_000 ether, USER_1);
        initialBlock = block.number;
        // prevActionBlock.push(initialBlock);
        // vm.roll(initialBlock + 1);
    }

    function prevActionBlockLength() external view returns (uint256) {
        return prevActionBlock.length;
    }

    function createAndFundUser(address _asset, uint256 _initialBalance, address user) public {
        vm.deal(user, _initialBalance * 2);
        vm.prank(user);
        (bool success,) = _asset.call{ value: _initialBalance }("");
        require(success, "Weth mint failed");
    }

    function setPrevActionBlock(uint256 _blockNumber) public {
        prevActionBlock.push(_blockNumber);
    }

    function getPriceInfo(uint256 price) public pure returns (bytes memory data) {
        data = abi.encode(price);
    }

    function mockInitiateOpenPosition(bool autoValidate, address user) external returns (int24 _tick) {
        vm.startPrank(user);
        _asset.approve(address(this), type(uint256).max);

        uint128 currentPrice = 1000 ether;

        bytes memory priceData = getPriceInfo(block.number);

        uint128 liquidationTargetPriceUint = currentPrice - (currentPrice * 15 / 100);
        _tick = getEffectiveTickForPrice(liquidationTargetPriceUint);

        this.initiateOpenPosition(uint96(10 ether), _tick, priceData, "");

        // if auto validate true
        if (autoValidate) {
            // auto validate open position
            this.validateOpenPosition(priceData, priceData);
        }

        // store prev action bloc number
        setPrevActionBlock(block.number);
    }
}
