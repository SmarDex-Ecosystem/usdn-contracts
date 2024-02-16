// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { IUsdnProtocolActions } from "src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol.
 */
interface IUsdnProtocol is IUsdnProtocolActions {
    /**
     * @notice Initialize the protocol, making a first deposit and creating a first long position.
     * @dev This function can only be called once, and no other user action can be performed until it was called.
     * Consult the current oracle middleware implementation to know the expected format for the price data, using the
     * `ProtocolAction.Initialize` action.
     * The price validation might require payment according to the return value of the `validationCost` function of the
     * middleware.
     * @param depositAmount the amount of wstETH for the deposit.
     * @param longAmount the amount of wstETH for the long.
     * @param desiredLiqPrice the desired liquidation price for the long.
     * @param currentPriceData the current price data.
     */
    function initialize(
        uint128 depositAmount,
        uint128 longAmount,
        uint128 desiredLiqPrice,
        bytes calldata currentPriceData
    ) external payable;

    /**
     * @notice Set the fee basis points (0.01%).
     * @param feeBps The fee bps to be charged.
     * @dev Fees are charged when transfers occur between the vault and the long
     * @dev example: 50 bps -> 0.5%
     */
    function setFeeBps(uint16 feeBps) external;

    /**
     * @notice Set the fee collector address.
     * @param feeCollector The address of the fee collector.
     * @dev The fee collector is the address that receives the fees charged by the protocol
     * @dev The fee collector must be different from the zero address
     */
    function setFeeCollector(address feeCollector) external;

    /**
     * @notice Set the minimum amount of fees to be collected before they can be withdrawn
     * @param feeThreshold The minimum amount of fees to be collected before they can be withdrawn
     */
    function setFeeThreshold(uint256 feeThreshold) external;
}
