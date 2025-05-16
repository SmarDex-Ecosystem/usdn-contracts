// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IFeeManager is IERC165 {
    /**
     * @notice The Asset struct to hold the address of an asset and its amount.
     * @param assetAddress The address of the asset.
     * @param amount The amount of the asset.
     */
    struct Asset {
        address assetAddress;
        uint256 amount;
    }

    /**
     * @notice Gets the subscriber discount for a specific feedId.
     * @param subscriber The address of the subscriber to check for a discount.
     * @param feedId The feedId related to the discount.
     * @param token The address of the quote payment token.
     * @return The current subscriber discount.
     */
    function s_subscriberDiscounts(address subscriber, bytes32 feedId, address token) external view returns (uint256);

    /**
     * @notice Gets any subsidized LINK that is owed to the reward manager for a specific feedId.
     * @param feedId The feedId related to the link deficit.
     * @return The amount of link deficit.
     */
    function s_linkDeficit(bytes32 feedId) external view returns (uint256);

    /**
     * @notice Gets the LINK token address.
     * @return The address of the LINK token.
     */
    function i_linkAddress() external view returns (address);

    /**
     * @notice Gets the native token address.
     * @return The address of the native token.
     */
    function i_nativeAddress() external view returns (address);

    /**
     * @notice Gets the proxy contract address.
     * @return The address of the proxy contract.
     */
    function i_proxyAddress() external view returns (address);

    /**
     * @notice Gets the surcharge fee to be paid if paying in native.
     * @return The surcharge fee for native payments.
     */
    function s_nativeSurcharge() external view returns (uint256);

    /**
     * @notice Calculates the applied fee and reward from a report. If the sender is a subscriber, they will receive a
     * discount.
     * @param subscriber The address of the subscriber trying to verify.
     * @param report The report to calculate the fee for.
     * @param quoteAddress The address of the quote payment token.
     * @return feeData The calculated fee data.
     * @return rewardData The calculated reward data.
     * @return discount The current subscriber discount applied.
     */
    function getFeeAndReward(address subscriber, bytes memory report, address quoteAddress)
        external
        view
        returns (Asset memory feeData, Asset memory rewardData, uint256 discount);
}
