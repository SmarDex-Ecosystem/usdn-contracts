// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";
import { IUsdnProtocolVault } from "src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { IUsdn } from "src/interfaces/Usdn/IUsdn.sol";
import { UsdnProtocolLib } from "src/libraries/UsdnProtocolLib.sol";

abstract contract UsdnProtocolVault is IUsdnProtocolVault, UsdnProtocolCore {
    using SafeCast for int256;

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice, uint128 timestamp) public view returns (uint256 price_) {
        price_ = UsdnProtocolLib.calcUsdnPrice(
            vaultAssetAvailableWithFunding(currentPrice, timestamp).toUint256(),
            currentPrice,
            _usdn.totalSupply(),
            _usdnDecimals,
            _assetDecimals
        );
    }

    /// @inheritdoc IUsdnProtocolVault
    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        price_ = usdnPrice(currentPrice, uint128(block.timestamp));
    }

    /**
     * @notice Check if a USDN rebase is required and adjust divisor if needed.
     * @dev Note: only call this function after `_applyPnlAndFunding` has been called to update the balances.
     * @param assetPrice The current price of the underlying asset
     * @param ignoreInterval If true, then the price check will be performed regardless of when the last check happened
     * @return rebased_ Whether a rebase was performed
     */
    function _usdnRebase(uint128 assetPrice, bool ignoreInterval) internal returns (bool rebased_) {
        if (!ignoreInterval && block.timestamp - _lastRebaseCheck < _usdnRebaseInterval) {
            return false;
        }
        _lastRebaseCheck = block.timestamp;
        IUsdn usdn = _usdn;
        uint256 divisor = usdn.divisor();
        if (divisor <= _usdnMinDivisor) {
            // no need to rebase, the USDN divisor cannot go lower
            return false;
        }
        uint256 balanceVault = _balanceVault;
        uint8 usdnDecimals = _usdnDecimals;
        uint8 assetDecimals = _assetDecimals;
        uint256 usdnTotalSupply = usdn.totalSupply();
        uint256 uPrice =
            UsdnProtocolLib.calcUsdnPrice(balanceVault, assetPrice, usdnTotalSupply, usdnDecimals, assetDecimals);
        if (uPrice <= _usdnRebaseThreshold) {
            return false;
        }
        uint256 targetTotalSupply = UsdnProtocolLib.calcRebaseTotalSupply(
            balanceVault, assetPrice, _targetUsdnPrice, usdnDecimals, assetDecimals
        );
        uint256 newDivisor = UsdnProtocolLib.fullMulDiv(usdnTotalSupply, divisor, targetTotalSupply);
        usdn.rebase(newDivisor);
        rebased_ = true;
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset
     * @param amount The amount of asset to be converted into USDN
     * @param vaultBalance The balance of the vault (not used for initialization)
     * @param usdnTotalSupply The total supply of USDN (not used for initialization)
     * @param price The price of the asset (only used for initialization)
     * @return toMint_ The amount of USDN to mint
     * @dev The amount of USDN to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance.
     */
    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint256 price)
        internal
        view
        returns (uint256 toMint_)
    {
        if (vaultBalance == 0) {
            // initialization, we consider the USDN price to be 1 USD
            return
                UsdnProtocolLib.fullMulDiv(amount, price, 10 ** (_assetDecimals + _priceFeedDecimals - _usdnDecimals));
        }
        toMint_ = UsdnProtocolLib.fullMulDiv(amount, usdnTotalSupply, vaultBalance);
    }
}
