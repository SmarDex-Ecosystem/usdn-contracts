// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocolCore } from "src/interfaces/UsdnProtocol/IUsdnProtocolCore.sol";
import {
    ProtocolAction,
    PendingAction,
    DepositPendingAction,
    WithdrawalPendingAction,
    LongPendingAction,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";
import { SignedMath } from "src/libraries/SignedMath.sol";
import { DoubleEndedQueue } from "src/libraries/DoubleEndedQueue.sol";

abstract contract UsdnProtocolCoreEntry is UsdnProtocolBaseStorage {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using DoubleEndedQueue for DoubleEndedQueue.Deque;

    address public constant DEAD_ADDRESS = address(0xdead);

    uint256 public constant MAX_ACTIONABLE_PENDING_ACTIONS = 20;

    /* -------------------------- Public  functions ------------------------- */

    function funding(uint128 timestamp) public returns (int256 fund_, int256 oldLongExpo_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSelector(IUsdnProtocolCore.funding.selector, timestamp));
        require(success, "failed");
        (fund_, oldLongExpo_) = abi.decode(data, (int256, int256));
    }

    function longAssetAvailableWithFunding(uint128 currentPrice, uint128 timestamp)
        public
        returns (int256 available_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCore.longAssetAvailableWithFunding.selector, currentPrice, timestamp)
        );
        require(success, "failed");
        available_ = abi.decode(data, (int256));
    }

    function longTradingExpoWithFunding(uint128 currentPrice, uint128 timestamp) public returns (int256 expo_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolCore.longTradingExpoWithFunding.selector, currentPrice, timestamp)
        );
        require(success, "failed");
        expo_ = abi.decode(data, (int256));
    }

    function calcEMA(int256 lastFunding, uint128 secondsElapsed, uint128 emaPeriod, int256 previousEMA)
        public
        returns (int256)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(
                IUsdnProtocolCore.calcEMA.selector, lastFunding, secondsElapsed, emaPeriod, previousEMA
            )
        );
        require(success, "failed");
        return abi.decode(data, (int256));
    }
}
