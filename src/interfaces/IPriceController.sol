// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { PriceInfo } from "src/interfaces/IOracleMiddleware.sol";

/**
 * @title PriceController contract
 * @notice this contract is used to return the right price for the asset.
 * @dev return wstEth price.
 */
interface IPriceController {
    error WrongAsset();

    function adjustedPrice(PriceInfo memory price) external view returns (PriceInfo memory);

    function wstEth() external view returns (address);
}
