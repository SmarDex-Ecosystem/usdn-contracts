// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IFeeCollectorCallback } from "../UsdnProtocol/IFeeCollectorCallback.sol";

/**
 * @title IFeeCollector
 * @notice Interface for the minimum implementation of the fee collector contract
 */
interface IFeeCollector is IFeeCollectorCallback {
    function supportsInterface(bytes4 interfaceId) external view override returns (bool);
}
