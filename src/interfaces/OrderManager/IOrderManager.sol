// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IOrderManagerErrors } from "src/interfaces/OrderManager/IOrderManagerErrors.sol";
import { IOrderManagerEvents } from "src/interfaces/OrderManager/IOrderManagerEvents.sol";
import { IOrderManagerTypes } from "src/interfaces/OrderManager/IOrderManagerTypes.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

interface IOrderManager is IOrderManagerErrors, IOrderManagerEvents, IOrderManagerTypes {
    /**
     * @notice Get the divisor for basis point values
     * @return The basis points divisor
     */
    function BPS_DIVISOR() external returns (uint32);

    /// @notice Returns the address of the USDN protocol
    function getUsdnProtocol() external view returns (IUsdnProtocol);

    /**
     * @notice Deposit assets into this contract to be included in the next position
     * @dev If `to` is already in a position, they need to close it completely before adding more assets
     * @param amount The amount to deposit (in _assetDecimals)
     * @param to The address to assign the deposit to
     */
    function depositAssets(uint128 amount, address to) external;

    /**
     * @notice Withdraw assets if the user is not in a position yet
     * @dev If the entry position version of the user is lower than or equal to the current one,
     * the transaction will revert
     * @param amount The amount to withdraw (in _assetDecimals)
     * @param to The address to send the assets to
     */
    function withdrawPendingAssets(uint128 amount, address to) external;

    /// @notice Returns the version of the current position (0 means no position open)
    function getPositionVersion() external view returns (uint128);

    /**
     * @notice Returns the target imbalance to have on the long side after the creation of a position
     * @dev The creation of the position aims for this target, but does not guarantee hitting it
     * @return targetLongImbalance_ The target long imbalance
     */
    function getTargetLongImbalanceBps() external view returns (int256 targetLongImbalance_);

    /**
     * @notice Sets the target long imbalance to the provided value
     * @dev The provided value needs to be greater than the USDN protocol close position imbalance limit
     * @param targetLongImbalanceBps The new target imbalance (in basis points)
     */
    function setTargetLongImbalanceBps(int256 targetLongImbalanceBps) external;

    /// @notice Returns the data regarding the assets deposited by the provided user
    function getUserDepositData(address user) external view returns (UserDeposit memory userDeposit_);
}
