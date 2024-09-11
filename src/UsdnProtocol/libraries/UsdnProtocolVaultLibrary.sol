// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolVault } from "../../interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolUtilsLibrary as Utils } from "./UsdnProtocolUtilsLibrary.sol";

library UsdnProtocolVaultLibrary {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedMath for int256;
    using SafeTransferLib for address;

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /// @notice See {IUsdnProtocolVault}
    function usdnPrice(Types.Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (uint256 price_)
    {
        price_ = _calcUsdnPrice(
            vaultAssetAvailableWithFunding(s, currentPrice, timestamp).toUint256(),
            currentPrice,
            s._usdn.totalSupply(),
            s._assetDecimals
        );
    }

    /// @notice See {IUsdnProtocolVault}
    function usdnPrice(Types.Storage storage s, uint128 currentPrice) public view returns (uint256 price_) {
        price_ = usdnPrice(s, currentPrice, uint128(block.timestamp));
    }

    /// @notice See {IUsdnProtocolVault}
    function previewDeposit(Types.Storage storage s, uint256 amount, uint128 price, uint128 timestamp)
        public
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_)
    {
        int256 vaultBalance = vaultAssetAvailableWithFunding(s, price, timestamp);
        if (vaultBalance <= 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }
        IUsdn usdn = s._usdn;
        uint256 amountAfterFees = amount - FixedPointMathLib.fullMulDiv(amount, s._vaultFeeBps, Constants.BPS_DIVISOR);
        usdnSharesExpected_ = Utils._calcMintUsdnShares(amountAfterFees, uint256(vaultBalance), usdn.totalShares());
        sdexToBurn_ = Utils._calcSdexToBurn(usdn.convertToTokens(usdnSharesExpected_), s._sdexBurnOnDepositRatio);
    }

    /// @notice See {IUsdnProtocolVault}
    function previewWithdraw(Types.Storage storage s, uint256 usdnShares, uint128 price, uint128 timestamp)
        public
        view
        returns (uint256 assetExpected_)
    {
        int256 available = vaultAssetAvailableWithFunding(s, price, timestamp);
        if (available < 0) {
            return 0;
        }
        assetExpected_ = Utils._calcBurnUsdn(usdnShares, uint256(available), s._usdn.totalShares(), s._vaultFeeBps);
    }

    /// @notice See {IUsdnProtocolVault}
    function vaultAssetAvailableWithFunding(Types.Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }

        (int256 fundAsset,) = Core._fundingAsset(s, timestamp, s._EMA);

        if (fundAsset < 0) {
            available_ = _vaultAssetAvailable(s, currentPrice).safeAdd(fundAsset);
        } else {
            int256 fee = fundAsset * Utils.toInt256(s._protocolFeeBps) / int256(Constants.BPS_DIVISOR);
            available_ = _vaultAssetAvailable(s, currentPrice).safeAdd(fundAsset - fee);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                              Internal function                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param s The storage of the protocol
     * @param currentPrice Current price
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(Types.Storage storage s, uint128 currentPrice)
        public
        view
        returns (int256 available_)
    {
        available_ =
            Utils._vaultAssetAvailable(s._totalExpo, s._balanceVault, s._balanceLong, currentPrice, s._lastPrice);
    }

    /**
     * @notice Calculate the price of the USDN token as a function of its total supply, the vault balance and the
     * underlying asset price
     * @param vaultBalance The vault balance
     * @param assetPrice The price of the asset
     * @param usdnTotalSupply The total supply of the USDN token
     * @param assetDecimals The number of decimals of the underlying asset
     * @return price_ The price of the USDN token
     */
    function _calcUsdnPrice(uint256 vaultBalance, uint128 assetPrice, uint256 usdnTotalSupply, uint8 assetDecimals)
        public
        pure
        returns (uint256 price_)
    {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** Constants.TOKENS_DECIMALS, usdnTotalSupply * 10 ** assetDecimals
        );
    }

    /**
     * @notice Calculate the required USDN total supply to reach `targetPrice`
     * @param vaultBalance The balance of the vault
     * @param assetPrice The price of the underlying asset
     * @param targetPrice The target USDN price to reach
     * @param assetDecimals The number of decimals of the asset
     * @return totalSupply_ The required total supply to achieve `targetPrice`
     */
    function _calcRebaseTotalSupply(uint256 vaultBalance, uint128 assetPrice, uint128 targetPrice, uint8 assetDecimals)
        public
        pure
        returns (uint256 totalSupply_)
    {
        totalSupply_ = FixedPointMathLib.fullMulDiv(
            vaultBalance,
            uint256(assetPrice) * 10 ** Constants.TOKENS_DECIMALS,
            uint256(targetPrice) * 10 ** assetDecimals
        );
    }

    /**
     * @notice Check if a USDN rebase is required and adjust the divisor if needed
     * @dev Note: only call this function after `_applyPnlAndFunding` has been called to update the balances
     * @param s The storage of the protocol
     * @param assetPrice The current price of the underlying asset
     * @param ignoreInterval If true, then the price check will be performed regardless of when the last check happened
     * @return rebased_ Whether a rebase was performed
     * @return callbackResult_ The rebase callback result, if any
     */
    function _usdnRebase(Types.Storage storage s, uint128 assetPrice, bool ignoreInterval)
        public
        returns (bool rebased_, bytes memory callbackResult_)
    {
        if (!ignoreInterval && block.timestamp - s._lastRebaseCheck < s._usdnRebaseInterval) {
            return (false, callbackResult_);
        }
        s._lastRebaseCheck = block.timestamp;
        IUsdn usdn = s._usdn;
        uint256 divisor = usdn.divisor();
        if (divisor <= s._usdnMinDivisor) {
            // no need to rebase, the USDN divisor cannot go lower
            return (false, callbackResult_);
        }
        uint256 balanceVault = s._balanceVault;
        uint8 assetDecimals = s._assetDecimals;
        uint256 usdnTotalSupply = usdn.totalSupply();
        uint256 uPrice = _calcUsdnPrice(balanceVault, assetPrice, usdnTotalSupply, assetDecimals);
        if (uPrice <= s._usdnRebaseThreshold) {
            return (false, callbackResult_);
        }
        uint256 targetTotalSupply = _calcRebaseTotalSupply(balanceVault, assetPrice, s._targetUsdnPrice, assetDecimals);
        uint256 newDivisor = FixedPointMathLib.fullMulDiv(usdnTotalSupply, divisor, targetTotalSupply);
        // since the USDN token can call a handler after the rebase, we want to make sure we do not block the user
        // action in case the rebase fails
        try usdn.rebase(newDivisor) returns (bool rebased, uint256, bytes memory callbackResult) {
            rebased_ = rebased;
            callbackResult_ = callbackResult;
        } catch { }
    }
}
