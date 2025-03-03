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

    /// @notice list of subscribers and their discounts subscriberDiscounts
    function s_subscriberDiscounts(address subscriber, bytes32 feedId, address token) external view returns (uint256);

    /// @notice keep track of any subsidized link that is owed to the reward manager.
    function s_linkDeficit(bytes32 feedId) external view returns (uint256);

    /// @notice the LINK token address
    function i_linkAddress() external view returns (address);

    /// @notice the native token address
    function i_nativeAddress() external view returns (address);

    /// @notice the proxy address
    function i_proxyAddress() external view returns (address);

    /// @notice the surcharge fee to be paid if paying in native
    function s_nativeSurcharge() external view returns (uint256);

    /**
     * @notice Calculate the applied fee and the reward from a report. If the sender is a subscriber, they will receive
     * a discount.
     * @param subscriber address trying to verify
     * @param report report to calculate the fee for
     * @param quoteAddress address of the quote payment token
     * @return (fee, reward, totalDiscount) fee and the reward data with the discount applied
     */
    function getFeeAndReward(address subscriber, bytes memory report, address quoteAddress)
        external
        view
        returns (Asset memory, Asset memory, uint256);
}
