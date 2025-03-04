// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IFeeManager is IERC165 {
    /**
     * @notice The asset struct to hold the address of an asset and amount.
     * @param assetAddress The address of the asset.
     * @param amount The asset amount.
     */
    struct Asset {
        address assetAddress;
        uint256 amount;
    }

    /**
     * @notice Gets the  subscriber discount for a specific feedId.
     * @param subscriber The subscriber address to check for a discount.
     * @param feedId The discount related feedId.
     * @param token The address of the quote payment token.
     * @return The current subscriber discount.
     */
    function s_subscriberDiscounts(address subscriber, bytes32 feedId, address token) external view returns (uint256);

    /**
     * @notice Gets any subsidized link that is owed to the reward manager.
     * @param feedId The link related feedId.
     * @return The link amount.
     */
    function s_linkDeficit(bytes32 feedId) external view returns (uint256);

    /**
     * @notice Gets the LINK token address.
     * @return The link address.
     */
    function i_linkAddress() external view returns (address);

    /**
     * @notice Gets the native token address.
     * @return The native token address.
     */
    function i_nativeAddress() external view returns (address);

    /**
     * @notice Gets the native token address.
     * @return The native token address.
     */
    function i_proxyAddress() external view returns (address);

    /**
     * @notice Gets the surcharge fee to be paid if paying in native.
     * @return The surcharge native fee.
     */
    function s_nativeSurcharge() external view returns (uint256);

    /**
     * @notice Calculate the applied fee and the reward from a report. If the sender is a subscriber, they will receive
     * a discount.
     * @param subscriber address trying to verify
     * @param report report to calculate the fee for
     * @param quoteAddress address of the quote payment token
     * @return The fee data.
     * @return The reward data.
     * @return The current discount.
     */
    function getFeeAndReward(address subscriber, bytes memory report, address quoteAddress)
        external
        view
        returns (Asset memory, Asset memory, uint256);
}
