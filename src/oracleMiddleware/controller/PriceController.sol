// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { PriceInfo, Assets } from "src/interfaces/IOracleMiddleware.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { IPriceController } from "src/interfaces/IPriceController.sol";

/**
 * @title PriceController contract
 * @notice this contract is used to return the right price for the asset.
 * @dev return wstEth price.
 */
contract PriceController is IPriceController {
    IWstETH internal immutable _wstEth;

    constructor(IWstETH wstEth_) {
        _wstEth = wstEth_;
    }

    function adjustedPrice(PriceInfo memory price) external view override returns (PriceInfo memory) {
        Assets asset = price.asset;
        // case wstEth
        if (asset == Assets.wstEth) {
            return price;

            // case stEth
        } else if (asset == Assets.stEth) {
            // wstEth ratio for one stEth
            uint256 tokensPerStEth = _wstEth.tokensPerStEth();
            // adjusted price
            return PriceInfo({
                price: tokensPerStEth * price.price / 1 ether,
                neutralPrice: tokensPerStEth * price.neutralPrice / 1 ether,
                timestamp: price.timestamp,
                asset: price.asset
            });

            // wrong asset
        } else {
            revert WrongAsset();
        }
    }

    // wsteth contract address
    function wstEth() external view override returns (address) {
        return address(_wstEth);
    }
}
