// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { ADMIN, USER_1, USER_2, USER_3, USER_4 } from "../../../../utils/Constants.sol";
import { Sdex } from "../../../../utils/Sdex.sol";
import { WstETH } from "../../../../utils/WstEth.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../../src/UsdnProtocol//libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolFallback } from "../../../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { UsdnProtocolImpl } from "../../../../../src/UsdnProtocol/UsdnProtocolImpl.sol";
import { UsdnProtocolCoreLibrary as Core } from "../../../../../src/UsdnProtocol/libraries/UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolLongLibrary as Long } from "../../../../../src/UsdnProtocol/libraries/UsdnProtocolLongLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from
    "../../../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { UsdnProtocolVaultLibrary as Vault } from
    "../../../../../src/UsdnProtocol/libraries/UsdnProtocolVaultLibrary.sol";
import { PriceInfo } from "../../../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { HugeUint } from "../../../../../src/libraries/HugeUint.sol";

/**
 * @notice A handler for invariant testing of the USDN protocol
 * @dev This handler does not perform input validation and might result in reverted transactions
 * To perform invariant testing without unexpected reverts, use UsdnProtocolSafeHandler
 */
contract UsdnProtocolHandler is UsdnProtocolImpl, UsdnProtocolFallback, Test {
    WstETH immutable _mockAsset;
    Sdex immutable _mockSdex;

    constructor(WstETH mockAsset, Sdex mockSdex) {
        _mockAsset = mockAsset;
        _mockSdex = mockSdex;
    }

    /* ------------------------ Invariant testing helpers ----------------------- */

    function mine(uint256 rand) external {
        uint256 blocks = rand % 9;
        blocks++;
        emit log_named_uint("mining blocks", blocks);
        skip(12 * blocks);
        vm.roll(block.number + blocks);
    }

    function senders() public pure returns (address[] memory senders_) {
        senders_ = new address[](5);
        senders_[0] = ADMIN;
        senders_[1] = USER_1;
        senders_[2] = USER_2;
        senders_[3] = USER_3;
        senders_[4] = USER_4;
    }

    /* ----------------------- Exposed internal functions ----------------------- */

    function i_getTickFromDesiredLiqPrice(
        uint128 desiredLiqPriceWithoutPenalty,
        uint256 assetPrice,
        uint256 longTradingExpo,
        HugeUint.Uint512 memory accumulator,
        int24 tickSpacing,
        uint24 liquidationPenalty
    ) external pure returns (int24 tickWithPenalty_, uint128 liqPriceWithoutPenalty_) {
        return Long._getTickFromDesiredLiqPrice(
            desiredLiqPriceWithoutPenalty, assetPrice, longTradingExpo, accumulator, tickSpacing, liquidationPenalty
        );
    }

    function i_calcPositionTotalExpo(uint128 amount, uint128 startPrice, uint128 liquidationPrice)
        external
        pure
        returns (uint128 totalExpo_)
    {
        return Utils._calcPositionTotalExpo(amount, startPrice, liquidationPrice);
    }

    /* -------------------------------- Internal -------------------------------- */

    function _getPreviousActionsData(address validator) internal view returns (PreviousActionsData memory) {
        (PendingAction[] memory actions, uint128[] memory rawIndices) = Vault.getActionablePendingActions(s, validator);
        return PreviousActionsData({ priceData: new bytes[](actions.length), rawIndices: rawIndices });
    }

    function _minDeposit() internal returns (uint128 minDeposit_) {
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 vaultBalance = s._balanceVault;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            vaultBalance =
                Vault.vaultAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        // minimum USDN shares to mint for burning 1 wei of SDEX
        uint256 minUsdnShares = FixedPointMathLib.divUp(
            Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR * s._usdn.divisor(), s._sdexBurnOnDepositRatio
        );
        // minimum USDN shares to mint 1 wei of USDN tokens
        uint256 halfDivisor = FixedPointMathLib.divUp(s._usdn.divisor(), 2);
        if (halfDivisor > minUsdnShares) {
            minUsdnShares = halfDivisor;
        }
        // minimum deposit that respects both conditions above
        minDeposit_ = uint128(
            FixedPointMathLib.fullMulDiv(
                minUsdnShares,
                vaultBalance * Constants.BPS_DIVISOR,
                s._usdn.totalShares() * (Constants.BPS_DIVISOR - s._vaultFeeBps)
            )
        );
        // if the minimum deposit is less than 1 wei of assets, set it to 1 wei (can't deposit 0)
        if (minDeposit_ == 0) {
            minDeposit_ = 1;
        }
    }

    function _maxDeposit() internal returns (uint128 maxDeposit_) {
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 longBalance = s._balanceLong;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            longBalance = Core.longAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        uint256 vaultBalance = s._balanceVault;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            vaultBalance =
                Vault.vaultAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        int256 longTradingExpo = int256(s._totalExpo - longBalance);
        int256 maxDeposit = (s._depositExpoImbalanceLimitBps * longTradingExpo / int256(Constants.BPS_DIVISOR))
            + longTradingExpo - int256(vaultBalance) - int256(s._pendingBalanceVault);
        if (maxDeposit < 0) {
            return 0;
        }
        maxDeposit_ = uint128(_bound(uint256(maxDeposit), 0, type(uint128).max));
    }

    function _maxWithdrawal(uint256 balance) internal returns (uint152 maxWithdrawal_) {
        PriceInfo memory price = s._oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateWithdrawal, ""
        );
        uint256 vaultBalance = s._balanceVault;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            vaultBalance =
                Vault.vaultAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        int256 v = int256(vaultBalance);
        uint256 longBalance = s._balanceLong;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            longBalance = Core.longAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        uint256 longTradingExpo = s._totalExpo - longBalance;
        int256 l = int256(longTradingExpo);
        int256 b = int256(Constants.BPS_DIVISOR);
        int256 t = int256(s._usdn.totalShares());
        int256 p = int256(s._pendingBalanceVault);
        int256 f = int256(uint256(s._vaultFeeBps));
        int256 maxWithdrawal = b * t * (b * (p + v - l) + s._withdrawalExpoImbalanceLimitBps * (p + v))
            / (v * (b - f) * (b - s._withdrawalExpoImbalanceLimitBps));
        if (maxWithdrawal < 0) {
            return 0;
        }
        if (maxWithdrawal > int256(balance)) {
            maxWithdrawal = int256(balance);
        }
        maxWithdrawal_ = uint152(_bound(uint256(maxWithdrawal), 0, type(uint152).max));
    }

    function _minLeverageTick() internal returns (int24 tick_) {
        PriceInfo memory price = s._oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateOpenPosition, ""
        );
        uint128 adjustedPrice = uint128(price.price + price.price * s._positionFeeBps / Constants.BPS_DIVISOR);
        uint128 liqPriceWithoutPenalty = Utils._getLiquidationPrice(adjustedPrice, uint128(s._minLeverage));
        (tick_,) = Long._getTickFromDesiredLiqPrice(
            liqPriceWithoutPenalty,
            s._lastPrice,
            Core.longTradingExpoWithFunding(s, s._lastPrice, uint128(block.timestamp)),
            s._liqMultiplierAccumulator,
            s._tickSpacing,
            s._liquidationPenalty
        );
        tick_ += s._tickSpacing; // because of the rounding down
    }

    function _maxLeverageTick() internal returns (int24 tick_) {
        PriceInfo memory price = s._oracleMiddleware.parseAndValidatePrice(
            "", uint128(block.timestamp), ProtocolAction.InitiateOpenPosition, ""
        );
        uint128 adjustedPrice = uint128(price.price + price.price * s._positionFeeBps / Constants.BPS_DIVISOR);
        uint128 liqPriceWithoutPenalty = Utils._getLiquidationPrice(adjustedPrice, uint128(s._maxLeverage));
        (tick_,) = Long._getTickFromDesiredLiqPrice(
            liqPriceWithoutPenalty,
            s._lastPrice,
            Core.longTradingExpoWithFunding(s, s._lastPrice, uint128(block.timestamp)),
            s._liqMultiplierAccumulator,
            s._tickSpacing,
            s._liquidationPenalty
        );
    }

    function _maxLongAmount(uint128 entryPrice, uint128 liqPriceWithoutPenalty) internal returns (uint128 amount_) {
        PriceInfo memory price =
            s._oracleMiddleware.parseAndValidatePrice("", uint128(block.timestamp), ProtocolAction.InitiateDeposit, "");
        uint256 longBalance = s._balanceLong;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            longBalance = Core.longAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        uint256 vaultBalance = s._balanceVault;
        if (price.timestamp >= s._lastUpdateTimestamp) {
            vaultBalance =
                Vault.vaultAssetAvailableWithFunding(s, uint128(price.neutralPrice), uint128(price.timestamp));
        }
        uint256 maxLongTradingExpo =
            vaultBalance * (Constants.BPS_DIVISOR + uint256(s._openExpoImbalanceLimitBps)) / Constants.BPS_DIVISOR;
        uint256 longTradingExpo = s._totalExpo - longBalance;
        if (longTradingExpo >= maxLongTradingExpo) {
            return 0;
        }
        uint256 newPosTradingExpo = maxLongTradingExpo - longTradingExpo;
        uint256 amount = (entryPrice * newPosTradingExpo / liqPriceWithoutPenalty) - newPosTradingExpo;
        amount_ = uint128(_bound(amount, s._minLongPosition, type(uint128).max));
    }
}
