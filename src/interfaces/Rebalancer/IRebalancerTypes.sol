// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { PositionId, Position } from "../UsdnProtocol/IUsdnProtocolTypes.sol";

interface IRebalancerTypes {
    /**
     * @notice The deposit data of a user
     * @param amount The amount of assets the user deposited
     * @param entryPositionVersion The position version the user entered at
     */
    struct UserDeposit {
        uint128 amount;
        uint128 entryPositionVersion;
    }

    /**
     * @notice The data for a version of the position
     * @dev The difference between the amount here and the amount saved in the USDN protocol is the liquidation bonus
     * @param amount The amount of assets used as collateral to open the position
     * @param entryAccMultiplier The accumulated PnL multiplier of all the positions up to this one
     * @param id The ID of the position in the USDN protocol
     */
    struct PositionData {
        uint128 amount;
        uint256 entryAccMultiplier;
        PositionId id;
    }

    /**
     * @dev Structure to hold the transient data during `initiateClosePosition`
     * @param userDepositData The user deposit data
     * @param remainingAssets The remaining rebalancer assets
     * @param positionVersion The current rebalancer position version
     * @param currentPositionData The current rebalancer position data
     * @param amountToCloseWithoutBonus The user amount to close without bonus
     * @param amountToClose The user amount to close including bonus
     * @param protocolPosition The protocol rebalancer position
     */
    struct InitiateCloseData {
        UserDeposit userDepositData;
        uint128 remainingAssets;
        uint256 positionVersion;
        PositionData currentPositionData;
        uint256 amountToCloseWithoutBonus;
        uint256 amountToClose;
        Position protocolPosition;
    }
}
