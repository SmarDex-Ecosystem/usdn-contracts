// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolCore } from "src/UsdnProtocol/UsdnProtocolCore.sol";

abstract contract UsdnProtocolVault is UsdnProtocolCore {
    using SafeCast for int256;

    function usdnPrice(uint128 currentPrice) public view returns (uint256 price_) {
        price_ = (
            vaultAssetAvailableWithFunding(currentPrice, uint128(block.timestamp)).toUint256() * uint256(currentPrice)
                * 10 ** _usdnDecimals
        ) / (_usdn.totalSupply() * 10 ** _assetDecimals);
    }

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
