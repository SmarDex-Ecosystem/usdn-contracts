// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { IUsdnProtocolVault } from "../interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { IUsdn } from "../interfaces/Usdn/IUsdn.sol";
import { Storage } from "./UsdnProtocolBaseStorage.sol";
import { UsdnProtocolCoreLibrary as coreLib } from "./UsdnProtocolCoreLibrary.sol";
import { UsdnProtocolActionsLibrary as actionsLib } from "./UsdnProtocolActionsLibrary.sol";
import { PositionId, Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "../libraries/SignedMath.sol";
import { IUsdnProtocolErrors } from "./../interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { InitializableReentrancyGuard } from "../utils/InitializableReentrancyGuard.sol";

/**
 * @notice Emitted when a user initiates the opening of a long position
 * @param owner The address that owns the position
 * @param validator The address of the validator that will validate the position
 * @param timestamp The timestamp of the action
 * @param totalExpo The initial total expo of the position (pending validation)
 * @param amount The amount of assets that were deposited as collateral
 * @param startPrice The asset price at the moment of the position creation (pending validation)
 * @param posId The unique position identifier
 */
event InitiatedOpenPosition(
    address indexed owner,
    address indexed validator,
    uint40 timestamp,
    uint128 totalExpo,
    uint128 amount,
    uint128 startPrice,
    PositionId posId
);

/**
 * @notice Emitted when a user validates the opening of a long position
 * @param owner The address that owns the position
 * @param validator The address of the validator that validated the position
 * @param totalExpo The total expo of the position
 * @param newStartPrice The asset price at the moment of the position creation (final)
 * @param posId The unique position identifier
 * If changed compared to `InitiatedOpenLong`, then `LiquidationPriceUpdated` will be emitted too
 */
event ValidatedOpenPosition(
    address indexed owner, address indexed validator, uint128 totalExpo, uint128 newStartPrice, PositionId posId
);

/**
 * @notice Emitted when a user initiates a deposit
 * @param to The address that will receive the USDN tokens
 * @param validator The address of the validator that will validate the deposit
 * @param amount The amount of assets that were deposited
 * @param timestamp The timestamp of the action
 */
event InitiatedDeposit(address indexed to, address indexed validator, uint256 amount, uint256 timestamp);

/**
 * @notice Emitted when a user validates a deposit
 * @param to The address that received the USDN tokens
 * @param validator The address of the validator that validated the deposit
 * @param amountDeposited The amount of assets that were deposited
 * @param usdnMinted The amount of USDN that was minted
 * @param timestamp The timestamp of the InitiatedDeposit action
 */
event ValidatedDeposit(
    address indexed to, address indexed validator, uint256 amountDeposited, uint256 usdnMinted, uint256 timestamp
);

library UsdnProtocolVaultLibrary {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SignedMath for int256;
    using SafeTransferLib for address;

    // / @inheritdoc IUsdnProtocolVault
    function usdnPrice(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (uint256 price_)
    {
        price_ = _calcUsdnPrice(
            s,
            vaultAssetAvailableWithFunding(s, currentPrice, timestamp).toUint256(),
            currentPrice,
            s._usdn.totalSupply(),
            s._assetDecimals
        );
    }

    // / @inheritdoc IUsdnProtocolVault
    function usdnPrice(Storage storage s, uint128 currentPrice) external view returns (uint256 price_) {
        price_ = usdnPrice(s, currentPrice, uint128(block.timestamp));
    }

    // / @inheritdoc IUsdnProtocolVault
    function previewDeposit(Storage storage s, uint256 amount, uint128 price, uint128 timestamp)
        external
        view
        returns (uint256 usdnSharesExpected_, uint256 sdexToBurn_)
    {
        // apply fees on price
        uint128 depositPriceWithFees = price - price * s._vaultFeeBps / uint128(s.BPS_DIVISOR);
        usdnSharesExpected_ = _calcMintUsdnShares(
            s,
            amount,
            vaultAssetAvailableWithFunding(s, depositPriceWithFees, timestamp).toUint256(),
            s._usdn.totalShares(),
            depositPriceWithFees
        );
        sdexToBurn_ = _calcSdexToBurn(s, s._usdn.convertToTokens(usdnSharesExpected_), s._sdexBurnOnDepositRatio);
    }

    // / @inheritdoc IUsdnProtocolVault
    function previewWithdraw(Storage storage s, uint256 usdnShares, uint256 price, uint128 timestamp)
        external
        view
        returns (uint256 assetExpected_)
    {
        // apply fees on price
        uint128 withdrawalPriceWithFees = (price + price * s._vaultFeeBps / s.BPS_DIVISOR).toUint128();
        int256 available = vaultAssetAvailableWithFunding(s, withdrawalPriceWithFees, timestamp);
        if (available < 0) {
            return 0;
        }
        assetExpected_ = _calcBurnUsdn(usdnShares, uint256(available), s._usdn.totalShares());
    }

    // / @inheritdoc IUsdnProtocolBaseStorage
    function tickHash(int24 tick, uint256 version) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tick, version));
    }

    // / @inheritdoc IUsdnProtocolCore
    function vaultAssetAvailableWithFunding(Storage storage s, uint128 currentPrice, uint128 timestamp)
        public
        view
        returns (int256 available_)
    {
        if (timestamp < s._lastUpdateTimestamp) {
            revert IUsdnProtocolErrors.UsdnProtocolTimestampTooOld();
        }

        int256 ema = coreLib.calcEMA(s._lastFunding, timestamp - s._lastUpdateTimestamp, s._EMAPeriod, s._EMA);
        (int256 fundAsset,) = coreLib._fundingAsset(s, timestamp, ema);

        if (fundAsset < 0) {
            available_ = _vaultAssetAvailable(s, currentPrice).safeAdd(fundAsset);
        } else {
            int256 fee = fundAsset * coreLib._toInt256(s._protocolFeeBps) / int256(s.BPS_DIVISOR);
            available_ = _vaultAssetAvailable(s, currentPrice).safeAdd(fundAsset - fee);
        }
    }

    // / @inheritdoc IUsdnProtocol
    function removeBlockedPendingAction(Storage storage s, address validator, address payable to) external {
        uint256 pendingActionIndex = s._pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        coreLib._removeBlockedPendingAction(s, rawIndex, to, true);
    }

    // / @inheritdoc IUsdnProtocol
    function removeBlockedPendingActionNoCleanup(Storage storage s, address validator, address payable to) external {
        uint256 pendingActionIndex = s._pendingActions[validator];
        if (pendingActionIndex == 0) {
            // no pending action
            // use the `rawIndex` variant below if for some reason the `_pendingActions` mapping is messed up
            revert IUsdnProtocolErrors.UsdnProtocolNoPendingAction();
        }
        uint128 rawIndex = uint128(pendingActionIndex - 1);
        coreLib._removeBlockedPendingAction(s, rawIndex, to, false);
    }

    /**
     * @notice Check if the initialize parameters lead to a balanced protocol
     * @dev This function reverts if the imbalance is exceeded for the deposit or open long action
     * @param positionTotalExpo The total expo of the deployer's long position
     * @param longAmount The amount (collateral) of the deployer's long position
     * @param depositAmount The amount of assets for the deployer's deposit
     */
    function _checkInitImbalance(
        Storage storage s,
        uint128 positionTotalExpo,
        uint128 longAmount,
        uint128 depositAmount
    ) internal view {
        // _checkUninitialized(); // prevent using this function after initialization
        // TODO : check this solution
        InitializableReentrancyGuard(address(this))._checkUninitialized();

        int256 longTradingExpo = coreLib._toInt256(positionTotalExpo - longAmount);
        int256 depositLimit = s._depositExpoImbalanceLimitBps;
        if (depositLimit != 0) {
            int256 imbalanceBps =
                (coreLib._toInt256(depositAmount) - longTradingExpo) * int256(s.BPS_DIVISOR) / longTradingExpo;
            if (imbalanceBps > depositLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }
        }
        int256 openLimit = s._openExpoImbalanceLimitBps;
        if (openLimit != 0) {
            int256 imbalanceBps = (longTradingExpo - coreLib._toInt256(depositAmount)) * int256(s.BPS_DIVISOR)
                / coreLib._toInt256(depositAmount);
            if (imbalanceBps > openLimit) {
                revert IUsdnProtocolErrors.UsdnProtocolImbalanceLimitReached(imbalanceBps);
            }
        }
    }

    /**
     * @notice Create initial deposit
     * @dev To be called from `initialize`
     * @param amount The initial deposit amount
     * @param price The current asset price
     */
    function _createInitialDeposit(Storage storage s, uint128 amount, uint128 price) internal {
        // _checkUninitialized(); // prevent using this function after initialization
        // TODO : check this solution
        InitializableReentrancyGuard(address(this))._checkUninitialized();

        // transfer the wstETH for the deposit
        address(s._asset).safeTransferFrom(msg.sender, address(this), amount);
        s._balanceVault += amount;
        emit InitiatedDeposit(msg.sender, msg.sender, amount, block.timestamp);

        // calculate the total minted amount of USDN shares (vault balance and total supply are zero for now, we assume
        // the USDN price to be $1 per token)
        uint256 usdnSharesToMint = _calcMintUsdnShares(s, amount, 0, 0, price);
        uint256 minUsdnSharesSupply = s._usdn.convertToShares(s.MIN_USDN_SUPPLY);
        // mint the minimum amount and send it to the dead address so it can never be removed from the total supply
        s._usdn.mintShares(s.DEAD_ADDRESS, minUsdnSharesSupply);
        // mint the user's share
        uint256 mintSharesToUser = usdnSharesToMint - minUsdnSharesSupply;
        uint256 mintedTokens = s._usdn.mintShares(msg.sender, mintSharesToUser);

        emit ValidatedDeposit(s.DEAD_ADDRESS, s.DEAD_ADDRESS, 0, s.MIN_USDN_SUPPLY, block.timestamp);
        emit ValidatedDeposit(msg.sender, msg.sender, amount, mintedTokens, block.timestamp);
    }

    /**
     * @notice Create initial long position
     * @dev To be called from `initialize`
     * @param amount The initial position amount
     * @param price The current asset price
     * @param tick The tick corresponding to the liquidation price (without penalty)
     * @param totalExpo The total expo of the position
     */
    function _createInitialPosition(Storage storage s, uint128 amount, uint128 price, int24 tick, uint128 totalExpo)
        internal
    {
        // _checkUninitialized(); // prevent using this function after initialization
        // TODO : check this solution
        InitializableReentrancyGuard(address(this))._checkUninitialized();

        // transfer the wstETH for the long
        address(s._asset).safeTransferFrom(msg.sender, address(this), amount);

        // apply liquidation penalty to the deployer's liquidationPriceWithoutPenalty
        uint8 liquidationPenalty = s._liquidationPenalty;
        PositionId memory posId;
        posId.tick = tick + int24(uint24(liquidationPenalty)) * s._tickSpacing;
        Position memory long = Position({
            validated: true,
            user: msg.sender,
            amount: amount,
            totalExpo: totalExpo,
            timestamp: uint40(block.timestamp)
        });
        // save the position and update the state
        (posId.tickVersion, posId.index,) = actionsLib._saveNewPosition(s, posId.tick, long, liquidationPenalty);
        s._balanceLong += long.amount;
        emit InitiatedOpenPosition(msg.sender, msg.sender, long.timestamp, totalExpo, long.amount, price, posId);
        emit ValidatedOpenPosition(msg.sender, msg.sender, totalExpo, price, posId);
    }

    /**
     * @notice Available balance in the vault side if the price moves to `currentPrice` (without taking funding into
     * account)
     * @param currentPrice Current price
     * @return available_ The available balance in the vault side
     */
    function _vaultAssetAvailable(Storage storage s, uint128 currentPrice) internal view returns (int256 available_) {
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
    ) internal pure returns (int256 available_) {
        int256 totalBalance = balanceLong.toInt256().safeAdd(balanceVault.toInt256());
        int256 newLongBalance = coreLib._longAssetAvailable(totalExpo, balanceLong, newPrice, oldPrice);

        available_ = totalBalance.safeSub(newLongBalance);
    }

    /**
     * @notice Function to calculate the hash and version of a given tick
     * @param tick The tick
     * @return hash_ The hash of the tick
     * @return version_ The version of the tick
     */
    function _tickHash(Storage storage s, int24 tick) internal view returns (bytes32 hash_, uint256 version_) {
        version_ = s._tickVersion[tick];
        hash_ = tickHash(tick, version_);
    }

    /**
     * @notice Calculate the amount of assets received when burning USDN shares
     * @param usdnShares The amount of USDN shares
     * @param available The available asset in the vault
     * @param usdnTotalShares The total supply of USDN shares
     * @return assetExpected_ The expected amount of assets to be received
     */
    function _calcBurnUsdn(uint256 usdnShares, uint256 available, uint256 usdnTotalShares)
        internal
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
    function _calcUsdnPrice(
        Storage storage s,
        uint256 vaultBalance,
        uint128 assetPrice,
        uint256 usdnTotalSupply,
        uint8 assetDecimals
    ) internal view returns (uint256 price_) {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** s.TOKENS_DECIMALS, usdnTotalSupply * 10 ** assetDecimals
        );
    }

    /**
     * @notice Calculate the amount of SDEX to burn when minting USDN tokens
     * @param usdnAmount The amount of USDN to be minted
     * @param sdexBurnRatio The ratio of SDEX to burn for each minted USDN
     * @return sdexToBurn_ The amount of SDEX to burn for the given USDN amount
     */
    function _calcSdexToBurn(Storage storage s, uint256 usdnAmount, uint32 sdexBurnRatio)
        internal
        view
        returns (uint256 sdexToBurn_)
    {
        sdexToBurn_ = FixedPointMathLib.fullMulDiv(usdnAmount, sdexBurnRatio, s.SDEX_BURN_ON_DEPOSIT_DIVISOR);
    }

    /**
     * @notice Calculate the required USDN total supply to reach `targetPrice`
     * @param vaultBalance The balance of the vault
     * @param assetPrice The price of the underlying asset
     * @param targetPrice The target USDN price to reach
     * @param assetDecimals The number of decimals of the asset
     * @return totalSupply_ The required total supply to achieve `targetPrice`
     */
    function _calcRebaseTotalSupply(
        Storage storage s,
        uint256 vaultBalance,
        uint128 assetPrice,
        uint128 targetPrice,
        uint8 assetDecimals
    ) internal view returns (uint256 totalSupply_) {
        totalSupply_ = FixedPointMathLib.fullMulDiv(
            vaultBalance, uint256(assetPrice) * 10 ** s.TOKENS_DECIMALS, uint256(targetPrice) * 10 ** assetDecimals
        );
    }

    /**
     * @notice Check if a USDN rebase is required and adjust the divisor if needed
     * @dev Note: only call this function after `_applyPnlAndFunding` has been called to update the balances
     * @param assetPrice The current price of the underlying asset
     * @param ignoreInterval If true, then the price check will be performed regardless of when the last check happened
     * @return rebased_ Whether a rebase was performed
     * @return callbackResult_ The rebase callback result, if any
     */
    function _usdnRebase(Storage storage s, uint128 assetPrice, bool ignoreInterval)
        internal
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
        uint256 uPrice = _calcUsdnPrice(s, balanceVault, assetPrice, usdnTotalSupply, assetDecimals);
        if (uPrice <= s._usdnRebaseThreshold) {
            return (false, callbackResult_);
        }
        uint256 targetTotalSupply =
            _calcRebaseTotalSupply(s, balanceVault, assetPrice, s._targetUsdnPrice, assetDecimals);
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
     * @param vaultBalance The balance of the vault (not used for initialization)
     * @param usdnTotalShares The total supply of USDN (not used for initialization)
     * @param price The price of the asset (only used for initialization)
     * @return toMint_ The amount of USDN to mint
     * @dev The amount of USDN shares to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance, and
     * sharesUsdn = amountAsset * totalShares / vaultBalance
     */
    function _calcMintUsdnShares(
        Storage storage s,
        uint256 amount,
        uint256 vaultBalance,
        uint256 usdnTotalShares,
        uint256 price
    ) internal view returns (uint256 toMint_) {
        if (vaultBalance == 0) {
            // initialization, we consider the USDN price to be 1 USD
            // the conversion here is necessary since we calculate an amount in tokens and we want the corresponding
            // amount of shares
            return s._usdn.convertToShares(
                FixedPointMathLib.fullMulDiv(
                    amount, price, 10 ** (s._assetDecimals + s._priceFeedDecimals - s.TOKENS_DECIMALS)
                )
            );
        }
        // for subsequent calculations, we can simply mint a proportional number of shares corresponding to the new
        // assets deposited into the vault
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalShares, vaultBalance);
    }

    /**
     * @notice Get the lower 24 bits of the withdrawal amount (USDN shares)
     * @param usdnShares The amount of USDN shares
     * @return sharesLSB_ The 24 least significant bits of the USDN shares
     */
    function _calcWithdrawalAmountLSB(uint152 usdnShares) internal pure returns (uint24 sharesLSB_) {
        sharesLSB_ = uint24(usdnShares);
    }

    /**
     * @notice Get the higher 128 bits of the withdrawal amount (USDN shares)
     * @param usdnShares The amount of USDN shares
     * @return sharesMSB_ The 128 most significant bits of the USDN shares
     */
    function _calcWithdrawalAmountMSB(uint152 usdnShares) internal pure returns (uint128 sharesMSB_) {
        sharesMSB_ = uint128(usdnShares >> 24);
    }
}
