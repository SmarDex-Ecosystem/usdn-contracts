// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
    /**
     * @notice Calculates the amount of USDN to mint for a given amount of asset according to its current price.
     * @param amount The amount of asset that were deposited.
     * @param currentPrice The current price of the asset.
     */
    function _calcMintUsdn(uint256 amount, uint128 currentPrice) internal view returns (uint256 toMint_) {
        toMint_ = FixedPointMathLib.fullMulDiv(
            amount, currentPrice, 10 ** (_assetDecimals + _priceFeedDecimals - _usdnDecimals)
        );
    }
}
