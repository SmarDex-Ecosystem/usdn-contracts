// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
    using SafeCast for int256;

    function usdnPrice(uint128 currentPrice) public view returns (uint256 price_) {
        price_ = FixedPointMathLib.fullMulDiv(
            vaultAssetAvailableWithFunding(currentPrice, uint128(block.timestamp)).toUint256(),
            uint256(currentPrice) * 10 ** _usdnDecimals,
            _usdn.totalSupply() * 10 ** _assetDecimals
        );
    }

    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset
     * @param amount The amount of asset to mint USDN for.
     * @param vaultBalance The balance of the vault
     * @param usdnTotalSupply The total supply of USDN
     * @param price The price of the asset (only used for initialization)
     */
    function _calcMintUsdn(uint256 amount, uint256 vaultBalance, uint256 usdnTotalSupply, uint128 price)
        internal
        view
        returns (uint256 toMint_)
    {
        if (vaultBalance == 0) {
            // initialization, we consider the USDN price to be 1 USD
            return
                FixedPointMathLib.fullMulDiv(amount, price, 10 ** (_assetDecimals + _priceFeedDecimals - _usdnDecimals));
        }
        toMint_ = FixedPointMathLib.fullMulDiv(amount, usdnTotalSupply, vaultBalance);
    }
}
