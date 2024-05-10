// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

interface IOrderManagerTypes {
    /**
     * @notice The deposit data of a user
     * @param amount The amount of asset the user deposited
     * @param entryPositionVersion The position version the user entered at
     */
    struct UserDeposit {
        uint128 amount;
        uint128 entryPositionVersion;
    }

    /**
     * @notice The data for a version of the position
     * @param accMultiplier The accumulated PnL multiplier of all the positions up to this one
     * @param pnlMultiplier The PnL (as a multiplier) of the position, updated when the position is closed
     * @param liquidationCountAtOpen The liquidation count when the position was opened
     * @param positionId The ID of the position in the USDN protocol
     */
    struct PositionData {
        uint128 accMultiplierAtEntry;
        uint128 pnlMultiplier;
        uint128 liquidationCountAtOpen;
        PositionId positionId;
    }
}
