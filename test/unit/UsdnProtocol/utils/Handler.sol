// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { PendingAction } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { UsdnProtocol } from "src/UsdnProtocol/UsdnProtocol.sol";
import { TickMath } from "src/libraries/TickMath.sol";
import { IUsdn } from "src/interfaces/IUsdn.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
import { IOracleMiddleware } from "src/interfaces/IOracleMiddleware.sol";
/**
 * @title UsdnProtocolHandler
 * @dev Wrapper to aid in testing the protocol
 */

contract UsdnProtocolHandler is UsdnProtocol {
    constructor(IUsdn usdn, IERC20Metadata asset, IOracleMiddleware oracleMiddleware, int24 tickSpacing)
        UsdnProtocol(usdn, asset, oracleMiddleware, tickSpacing)
    { }

    // tick version
    function tickVersion(int24 _tick) external view returns (uint256) {
        return _tickVersion[_tick];
    }

    // tick hash
    function tickHash(int24 tick) external view returns (bytes32, uint256) {
        return _tickHash(tick);
    }

    // total expo by tick
    function totalExpoByTick(int24 tick) external view returns (uint256) {
        (bytes32 tHash,) = _tickHash(tick);
        return _totalExpoByTick[tHash];
    }

    // long positions length
    function longPositionsLength(int24 tick) external view returns (uint256) {
        (bytes32 tHash,) = _tickHash(tick);
        return _longPositions[tHash].length;
    }

    // positions in tick
    function positionsInTick(int24 tick) external view returns (uint256) {
        (bytes32 tHash,) = _tickHash(tick);
        return _positionsInTick[tHash];
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

    function liquidationMultiplier() external view returns (uint256) {
        return _liquidationMultiplier;
    }

    function setMinLeverage(uint256 minLeverage) external {
        _minLeverage = minLeverage;
    }

    function getMinLeverage() external view returns (uint256) {
        return _minLeverage;
    }

    function minimumPrice() external pure returns (uint256) {
        return TickMath.MIN_PRICE;
    }

    function longAssetAvailable(uint128 currentPrice) external view returns (int256) {
        return _longAssetAvailable(currentPrice);
    }

    function totalExpo() external view returns (uint256) {
        return _totalExpo;
    }

    function getLeverage(uint128 startPrice, uint128 liquidationPrice) external pure returns (uint128) {
        return _getLeverage(startPrice, liquidationPrice);
    }

    function liquidationPenalty() external view returns (uint24) {
        return _liquidationPenalty;
    }
}
