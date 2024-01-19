// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";

import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */

contract UsdnProtocolHandler is UsdnProtocol, Test {
    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing)
        UsdnProtocol(usdn, asset, oracleMiddleware, tickSpacing)
    { }

    // tick version
    function tickVersion(int24 _tick) external view returns (uint256) {
        return _tickVersion[_tick];
    }

    // total expo
    function totalExpo() external view returns (uint256) {
        return _totalExpo;
    }

    // tick hash
    function tickHash(int24 tick) external view returns (bytes32) {
        return _tickHash(tick);
    }

    // total expo by tick
    function totalExpoByTick(int24 tick) external view returns (uint256) {
        return _totalExpoByTick[_tickHash(tick)];
    }

    // long positions length
    function longPositionsLength(int24 tick) external view returns (uint256) {
        return _longPositions[_tickHash(tick)].length;
    }

    // positions in tick
    function positionsInTick(int24 tick) external view returns (uint256) {
        return _positionsInTick[_tickHash(tick)];
    }

    // max initialized tick
    function maxInitializedTick() external view returns (int24) {
        return _maxInitializedTick;
    }

    // total long position
    function totalLongPositions() external view returns (uint256) {
        return _totalLongPositions;
    }

    // fetch max liquidation execution
    function maxLiquidationIteration() external pure returns (uint16) {
        return MAX_LIQUIDATION_ITERATION;
    }

    function validationDeadline() external view returns (uint256) {
        return _validationDeadline;
    }

    function getUserPendingAction(address user) external returns (PendingAction memory) {
        return _getPendingAction(user, false); // do not clear
    }

    function balanceVault() external view returns (uint256) {
        return _balanceVault;
    }

    function vaultAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return _vaultAssetAvailable(currentPrice);
    }
}
