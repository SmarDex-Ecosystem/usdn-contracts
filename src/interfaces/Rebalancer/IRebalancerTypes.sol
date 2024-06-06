// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { PositionId } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
     * @param pnlMultiplier The PnL (as a multiplier) of the position when closed
     * @param id The ID of the position in the USDN protocol
     */
    struct PositionData {
        uint128 amount;
        uint128 entryAccMultiplier;
        uint128 pnlMultiplier;
        PositionId id;
    }
}
