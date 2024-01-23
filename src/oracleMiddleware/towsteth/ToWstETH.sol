// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";

/**
 * @title ToWstETH contract
 * @notice this contract is used to return the right price for the asset.
 * @dev return wstEth price.
 */
contract ToWstETH {
    IWstETH internal immutable _wstEth;

    constructor(address wstEth_) {
        _wstEth = IWstETH(wstEth_);
    }

    function toWstETH(PriceInfo memory price) public view returns (PriceInfo memory) {
        // wstEth ratio for one stEth
        uint256 tokensPerStEth = _wstEth.tokensPerStEth();
        // adjusted price
        return PriceInfo({
            price: tokensPerStEth * price.price / 1 ether,
            neutralPrice: tokensPerStEth * price.neutralPrice / 1 ether,
            timestamp: price.timestamp
        });
    }

    // wsteth contract address
    function wstEth() external view returns (address) {
        return address(_wstEth);
    }
}
