// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdn } from "../../interfaces/Usdn/IUsdn.sol";
import { IUsdnProtocolErrors } from "../../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes as Types } from "../../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { IUsdnProtocolVault } from "../../interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { SignedMath } from "../../libraries/SignedMath.sol";
import { UsdnProtocolActionsUtilsLibrary as ActionsUtils } from "./UsdnProtocolActionsUtilsLibrary.sol";
import { UsdnProtocolConstantsLibrary as Constants } from "./UsdnProtocolConstantsLibrary.sol";
import { UsdnProtocolCoreLibrary as Core } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolUtils as Utils } from "./UsdnProtocolUtils.sol";

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
        // apply fees on price
        uint128 depositPriceWithFees = uint128(price - uint256(price) * s._vaultFeeBps / Constants.BPS_DIVISOR);
        int256 vaultBalance = vaultAssetAvailableWithFunding(s, depositPriceWithFees, timestamp);
        if (vaultBalance <= 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }
        IUsdn usdn = s._usdn;
        usdnSharesExpected_ = _calcMintUsdnShares(amount, uint256(vaultBalance), usdn.totalShares());
        sdexToBurn_ = _calcSdexToBurn(usdn.convertToTokens(usdnSharesExpected_), s._sdexBurnOnDepositRatio);
    }

    /// @notice See {IUsdnProtocolVault}
    function previewWithdraw(Types.Storage storage s, uint256 usdnShares, uint256 price, uint128 timestamp)
        public
        view
        returns (uint256 assetExpected_)
    {
        // apply fees on price
        uint128 withdrawalPriceWithFees = (price + price * s._vaultFeeBps / Constants.BPS_DIVISOR).toUint128();
        int256 available = vaultAssetAvailableWithFunding(s, withdrawalPriceWithFees, timestamp);
        if (available < 0) {
            return 0;
        }
        assetExpected_ = _calcBurnUsdn(usdnShares, uint256(available), s._usdn.totalShares());
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
     * @notice Check if the initialize parameters lead to a balanced protocol
     * @param s The storage of the protocol
     * @dev This function reverts if the imbalance is exceeded for the deposit or open long action
     * @param positionTotalExpo The total expo of the deployer's long position
     * @param longAmount The amount (collateral) of the deployer's long position
     * @param depositAmount The amount of assets for the deployer's deposit
     */
    function _checkInitImbalance(
        Types.Storage storage s,
        uint128 positionTotalExpo,
        uint128 longAmount,
        uint128 depositAmount
    ) public view {
        int256 longTradingExpo = Utils.toInt256(positionTotalExpo - longAmount);
        int256 depositLimit = s._depositExpoImbalanceLimitBps;
        if (depositLimit != 0) {
            int256 imbalanceBps =
                (Utils.toInt256(depositAmount) - longTradingExpo) * int256(Constants.BPS_DIVISOR) / longTradingExpo;
            if (imbalanceBps > depositLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }
        }
        int256 openLimit = s._openExpoImbalanceLimitBps;
        if (openLimit != 0) {
            int256 imbalanceBps = (longTradingExpo - Utils.toInt256(depositAmount)) * int256(Constants.BPS_DIVISOR)
                / Utils.toInt256(depositAmount);
            if (imbalanceBps > openLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }
        }
    }

    /**
     * @notice Create initial deposit
     * @dev To be called from `initialize`
     * @param s The storage of the protocol
     * @param amount The initial deposit amount
     * @param price The current asset price
     */
    function _createInitialDeposit(Types.Storage storage s, uint128 amount, uint128 price) public {
        // transfer the wstETH for the deposit
        address(s._asset).safeTransferFrom(msg.sender, address(this), amount);
        s._balanceVault += amount;
        emit IUsdnProtocolEvents.InitiatedDeposit(msg.sender, msg.sender, amount, 0, block.timestamp, 0);

        // calculate the total minted amount of USDN shares (vault balance and total supply are zero for now, we assume
        // the USDN price to be $1 per token)
        // the decimals conversion here is necessary since we calculate an amount in tokens and we want the
        // corresponding amount of shares
        uint256 usdnSharesToMint = s._usdn.convertToShares(
            FixedPointMathLib.fullMulDiv(
                amount, price, 10 ** (s._assetDecimals + s._priceFeedDecimals - Constants.TOKENS_DECIMALS)
            )
        );
        IUsdn usdn = s._usdn;
        uint256 minUsdnSharesSupply = usdn.convertToShares(Constants.MIN_USDN_SUPPLY);
        // mint the minimum amount and send it to the dead address so it can never be removed from the total supply
        usdn.mintShares(Constants.DEAD_ADDRESS, minUsdnSharesSupply);
        // mint the user's share
        uint256 mintSharesToUser = usdnSharesToMint - minUsdnSharesSupply;
        uint256 mintedTokens = usdn.mintShares(msg.sender, mintSharesToUser);

        emit IUsdnProtocolEvents.ValidatedDeposit(
            Constants.DEAD_ADDRESS, Constants.DEAD_ADDRESS, 0, Constants.MIN_USDN_SUPPLY, block.timestamp
        );
        emit IUsdnProtocolEvents.ValidatedDeposit(msg.sender, msg.sender, amount, mintedTokens, block.timestamp);
    }

    /**
     * @notice Create initial long position
     * @dev To be called from `initialize`
     * @param s The storage of the protocol
     * @param amount The initial position amount
     * @param price The current asset price
     * @param tick The tick corresponding where the position should be stored
     * @param totalExpo The total expo of the position
     */
    function _createInitialPosition(
        Types.Storage storage s,
        uint128 amount,
        uint128 price,
        int24 tick,
        uint128 totalExpo
    ) public {
        // transfer the wstETH for the long
        address(s._asset).safeTransferFrom(msg.sender, address(this), amount);

        Types.PositionId memory posId;
        posId.tick = tick;
        Types.Position memory long = Types.Position({
            validated: true,
            user: msg.sender,
            amount: amount,
            totalExpo: totalExpo,
            timestamp: uint40(block.timestamp)
        });
        // save the position and update the state
        (posId.tickVersion, posId.index,) = ActionsUtils._saveNewPosition(s, posId.tick, long, s._liquidationPenalty);
        s._balanceLong += long.amount;
        emit IUsdnProtocolEvents.InitiatedOpenPosition(
            msg.sender, msg.sender, long.timestamp, totalExpo, long.amount, price, posId
        );
        emit IUsdnProtocolEvents.ValidatedOpenPosition(msg.sender, msg.sender, totalExpo, price, posId);
    }

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
        available_ = _vaultAssetAvailable(s._totalExpo, s._balanceVault, s._balanceLong, currentPrice, s._lastPrice);
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param totalExpo The total expo
     * @param balanceVault The (old) balance of the vault
     * @param balanceLong The (old) balance of the long side
     * @param newPrice The new price
     * @param oldPrice The old price when the old balances were updated
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(
        uint256 totalExpo,
        uint256 balanceVault,
        uint256 balanceLong,
        uint128 newPrice,
        uint128 oldPrice
    ) public pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = Core._longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);

        available_ = totalBalance.safeSub(newLongBalance);
    }

    /**
     * @notice Calculate the amount of assets received when burning USDN shares
     * @param usdnShares The amount of USDN shares
     * @param available The available asset in the vault
     * @param usdnTotalShares The total supply of USDN shares
     * @return assetExpected_ The expected amount of assets to be received
     */
    function _calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        public
        pure
        returns (uint256 assetExpected_)
    {
        // assetExpected = amountUsdn * usdnPrice / assetPrice = amountUsdn * assetAvailable / totalSupply
        //                 = shares * assetAvailable / usdnTotalShares
        assetExpected_ = FixedPointMathLib.fullMulDiv(usdnShares, available, usdnTotalShares);
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
     * @notice Calculate the amount of SDEX to burn when minting USDN tokens
     * @param usdnAmount The amount of USDN to be minted
     * @param sdexBurnRatio The ratio of SDEX to burn for each minted USDN
     * @return sdexToBurn_ The amount of SDEX to burn for the given USDN amount
     */
    function _calcSdexToBurn(uint256 usdnAmount, uint32 sdexBurnRatio) public pure returns (uint256 sdexToBurn_) {
        sdexToBurn_ = FixedPointMathLib.fullMulDiv(usdnAmount, sdexBurnRatio, Constants.SDEX_BURN_ON_DEPOSIT_DIVISOR);
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

    /**
     * @notice Calculates the amount of USDN shares to mint for a given amount of asset
     * @param amount The amount of asset to be converted into USDN
     * @param vaultBalance The balance of the vault
     * @param usdnTotalShares The total supply of USDN
     * @return toMint_ The amount of USDN to mint
     * @dev The amount of USDN shares to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance, and
     * sharesUsdn = amountAsset * totalShares / vaultBalance
     */
    function _calcMintUsdnShares(uint256 amount, uint256 vaultBalance, uint256 usdnTotalShares)
        public
        pure
        returns (uint256 toMint_)
    {
        if (vaultBalance == 0) {
            revert IUsdnProtocolErrors.UsdnProtocolEmptyVault();
        }
        // we simply mint a proportional number of shares corresponding to the new assets deposited into the vault
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalShares, vaultBalance);
    }

    /**
     * @notice Get the lower 24 bits of the withdrawal amount (USDN shares)
     * @param usdnShares The amount of USDN shares
     * @return sharesLSB_ The 24 least significant bits of the USDN shares
     */
    function _calcWithdrawalAmountLSB(uint152 usdnShares) public pure returns (uint24 sharesLSB_) {
        sharesLSB_ = uint24(usdnShares);
    }

    /**
     * @notice Get the higher 128 bits of the withdrawal amount (USDN shares)
     * @param usdnShares The amount of USDN shares
     * @return sharesMSB_ The 128 most significant bits of the USDN shares
     */
    function _calcWithdrawalAmountMSB(uint152 usdnShares) public pure returns (uint128 sharesMSB_) {
        sharesMSB_ = uint128(usdnShares >> 24);
    }
}
