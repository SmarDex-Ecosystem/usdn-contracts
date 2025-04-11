// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { StdStyle, console, console2 } from "forge-std/Test.sol";

import { FuzzBase } from "@perimetersec/fuzzlib/src/FuzzBase.sol";

import { BeforeAfter } from "../helper/BeforeAfter.sol";
import { PropertiesDescriptions } from "./PropertiesDescriptions.sol";

import { Usdn as usdnEnum } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";
import { PriceInfo } from "../../../src/interfaces/OracleMiddleware/IOracleMiddlewareTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

abstract contract PropertiesBase is FuzzBase, BeforeAfter, PropertiesDescriptions {
    function calculateUsdnOnDeposit(uint256 wstethPendingActions, Types.DepositPendingAction memory deposit)
        internal
        returns (uint256)
    {
        int256 available;

        PriceInfo memory currentPrice = usdnProtocol.i_getOraclePrice{ value: pythPrice }(
            Types.ProtocolAction.ValidateDeposit,
            deposit.timestamp,
            keccak256(abi.encodePacked(deposit.validator, deposit.timestamp)),
            createPythData()
        );

        uint256 balanceVault = deposit.balanceVault;
        if (currentPrice.price < deposit.assetPrice) {
            available = usdnProtocol.i_vaultAssetAvailable(
                deposit.totalExpo,
                deposit.balanceVault,
                deposit.balanceLong,
                uint128(currentPrice.price),
                deposit.assetPrice
            );

            if (available < 0) {
                balanceVault = 0;
            } else {
                balanceVault = uint256(available);
            }
        }

        uint256 feeAmount = (uint256(deposit.amount) * deposit.feeBps) / uint128(Constants.BPS_DIVISOR);

        uint128 amountAfterFees = uint128(deposit.amount - feeAmount);

        uint256 balanceVaultWithFees = balanceVault + feeAmount;

        uint256 expectedBalanceIncrease =
            Utils._calcMintUsdnShares(amountAfterFees, balanceVaultWithFees, deposit.usdnTotalShares);

        uint256 convertedTokens =
            usdn.i_convertToTokens(expectedBalanceIncrease, usdnEnum.Rounding.Closest, usdn.divisor());

        logCalculateUsdnOnDeposit(
            wstethPendingActions,
            deposit,
            balanceVault,
            currentPrice,
            available,
            amountAfterFees,
            expectedBalanceIncrease,
            convertedTokens
        );

        return convertedTokens;
    }

    function eqWithToleranceWei(uint256 a, uint256 b, uint256 maxWeiDiff, string memory reason) internal {
        if (a == b) return;

        uint256 diff;
        if (a > b) {
            diff = a - b;
        } else {
            diff = b - a;
        }

        if (diff > maxWeiDiff) {
            fl.t(false, reason);
        } else {
            fl.t(true, "Invariant ok, checked for: ");
        }
    }

    function eqWithTolerance(
        uint256 a,
        uint256 b,
        uint256 maxPercentDiff, //shoud have 18 decimals
        string memory reason
    ) internal {
        uint256 percentDiff;

        if (a == b) return;

        if (a > b) {
            percentDiff = ((a - b) * 1e18) / ((a + b) / 2);
        } else {
            percentDiff = ((b - a) * 1e18) / ((a + b) / 2);
        }

        if (percentDiff > maxPercentDiff) {
            fl.log("Percentage difference is bigger than expected", percentDiff);
            fl.t(false, reason);
        } else {
            fl.t(true, "Invariant ok, ckeched for: ");
        }
    }

    function eqWithTolerancePositiveInt(
        int256 intA,
        int256 intB,
        uint256 maxPercentDiff, //shoud have 18 decimals
        string memory reason
    ) internal {
        fl.t(intA >= 0, "A should be positive");
        fl.t(intB >= 0, "B should be positive");

        uint256 a = uint256(intA);
        uint256 b = uint256(intB);

        uint256 percentDiff;

        if (a == b) return;

        if (a > b) {
            percentDiff = ((a - b) * 1e18) / ((a + b) / 2);
        } else {
            percentDiff = ((b - a) * 1e18) / ((a + b) / 2);
        }

        if (percentDiff > maxPercentDiff) {
            fl.log("Percentage difference is bigger than expected", percentDiff);
            fl.t(false, reason);
        } else {
            fl.t(true, "Invariant ok, ckeched for: ");
        }
    }

    function logCalculateUsdnOnDeposit(
        uint256 wstethPendingActions,
        Types.DepositPendingAction memory deposit,
        uint256 balanceVault,
        PriceInfo memory currentPrice,
        int256 available,
        uint128 amountAfterFees,
        uint256 expectedBalanceIncrease,
        uint256 convertedTokens
    ) internal pure {
        console.log("");
        console.log(StdStyle.green("CALCULATE USDN ON DEPOSIT"));
        console.log(StdStyle.green("-----------------------------------------------------------"));
        console.log(StdStyle.green("  WstETH Pending Actions ........ %s"), wstethPendingActions);
        console.log(StdStyle.green("  Deposit Amount ................ %s"), deposit.amount);
        console.log(StdStyle.green("  Deposit Asset Price ........... %s"), deposit.assetPrice);
        console.log(StdStyle.green("  Deposit Timestamp ............. %s"), deposit.timestamp);
        console.log(StdStyle.green("  Deposit Fee BPS ............... %s"), deposit.feeBps);
        console.log(StdStyle.green("  Deposit Total Expo ............ %s"), deposit.totalExpo);
        console.log(StdStyle.green("  Deposit Balance Vault ......... %s"), deposit.balanceVault);
        console.log(StdStyle.green("  Deposit Balance Long .......... %s"), deposit.balanceLong);
        console.log(StdStyle.green("  Deposit USDN Total Shares ..... %s"), deposit.usdnTotalShares);
        console.log(StdStyle.green("  Balance Vault ................. %s"), balanceVault);
        console.log(StdStyle.green("  Current Price ................. %s"), currentPrice.price);
        console.log(StdStyle.green("  Available Asset ............... %s"), available);
        console.log(StdStyle.green("  Amount After Fees ............. %s"), amountAfterFees);
        console.log(StdStyle.green("  Expected Balance Increase ..... %s"), expectedBalanceIncrease);
        console.log(StdStyle.green("  Converted Tokens .............. %s"), convertedTokens);
        console.log(StdStyle.green("-----------------------------------------------------------"));
    }
}
