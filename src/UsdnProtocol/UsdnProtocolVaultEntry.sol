// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IUsdnProtocolVault } from "src/interfaces/UsdnProtocol/IUsdnProtocolVault.sol";
import { UsdnProtocolBaseStorage } from "src/UsdnProtocol/UsdnProtocolBaseStorage.sol";

abstract contract UsdnProtocolVaultEntry is UsdnProtocolBaseStorage {
    using SafeCast for int256;
    using SafeCast for uint256;

    function usdnPrice(uint128 currentPrice, uint128 timestamp) public returns (uint256 price_) {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSignature("usdnPrice(uint128,uint128)", currentPrice, timestamp)
        );
        require(success, "failed");
        price_ = abi.decode(data, (uint256));
    }

    function usdnPrice(uint128 currentPrice) external returns (uint256 price_) {
        (bool success, bytes memory data) =
            address(s._protocol).delegatecall(abi.encodeWithSignature("usdnPrice(uint128,uint128)", currentPrice));
        require(success, "failed");
        price_ = abi.decode(data, (uint256));
    }

    /**
     * @notice Calculate an estimation of assets received when withdrawing
     * @param usdnShares The amount of USDN shares
     * @param price The price of the asset
     * @param timestamp The timestamp of the operation
     * @return assetExpected_ The expected amount of asset to be received
     */
    function previewWithdraw(uint256 usdnShares, uint256 price, uint128 timestamp)
        public
        returns (uint256 assetExpected_)
    {
        (bool success, bytes memory data) = address(s._protocol).delegatecall(
            abi.encodeWithSelector(IUsdnProtocolVault.previewWithdraw.selector, usdnShares, price, timestamp)
        );
        require(success, "failed");
        assetExpected_ = abi.decode(data, (uint256));
    }
}
