// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IFeeCollectorCallback } from "../UsdnProtocol/IFeeCollectorCallback.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IFeeCollector
 * @notice Interface for the minimum implementation of the fee collector contract
 */
interface IFeeCollector is IFeeCollectorCallback, IERC165 {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external view override returns (bool);

    /// @inheritdoc IFeeCollectorCallback
    function feeCollectorCallback(uint256 feeAmount) external;
}
