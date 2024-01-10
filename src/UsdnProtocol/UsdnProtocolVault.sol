// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
    using SafeCast for int256;

    function usdnPrice(uint128 currentPrice, uint128 timestamp) public view returns (uint256 price_) {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultAssetAvailableWithFunding(currentPrice, timestamp).toUint256(),
            uint256(currentPrice) * 10 ** _usdnDecimals,
            _usdn.totalSupply() * 10 ** _assetDecimals
        );
    }

    function usdnPrice(uint128 currentPrice) external view returns (uint256 price_) {
        price_ = usdnPrice(currentPrice, uint128(block.timestamp));
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset
     * @param amount The amount of asset that were deposited.
     * @param currentPrice The current price of the asset, this is required to account for any pending funding or PnL
     * that wasn't reflected in the balances yet.
     * @dev The amount of USDN to mint is calculated as follows:
     * amountUsdn = amountAsset * priceAsset / priceUsdn,
     * but since priceUsdn = vaultBalance * priceAsset / totalSupply, we can simplify to
     * amountUsdn = amountAsset * totalSupply / vaultBalance.
     * After we have just updated the balances, vaultAssetAvailableWithFunding is equal to _balanceVault.
     */
    function _calcMintUsdn(uint256 amount, uint128 currentPrice) internal view returns (uint256 toMint_) {
        if (_balanceVault == 0) {
            // initialization, we consider the USDN price to be 1 USD
            return FixedPointMathLib.fullMulDiv(
                amount, currentPrice, 10 ** (_assetDecimals + _priceFeedDecimals - _usdnDecimals)
            );
        }
        uint256 vaultBalance = vaultAssetAvailableWithFunding(currentPrice, uint128(block.timestamp)).toUint256();
        toMint_ = FixedPointMathLib.fullMulDiv(amount, _usdn.totalSupply(), vaultBalance);
    }
}
