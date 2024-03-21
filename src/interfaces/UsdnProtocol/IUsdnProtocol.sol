// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolActions } from "src/interfaces/UsdnProtocol/IUsdnProtocolActions.sol";

/**
 * @title IUsdnProtocol
 * @notice Interface for the USDN protocol.
 */
interface IUsdnProtocol is IUsdnProtocolActions {
    /// @dev The minimum amount of wstETH for the initialization deposit and long.
    function MIN_INIT_DEPOSIT() external pure returns (uint256);

    /**
     * @notice Initialize the protocol, making a first deposit and creating a first long position.
     * @dev This function can only be called once, and no other user action can be performed until it was called.
     * Consult the current oracle middleware implementation to know the expected format for the price data, using the
     * `ProtocolAction.Initialize` action.
     * The price validation might require payment according to the return value of the `getValidationCost` function of
     * the middleware.
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
}
