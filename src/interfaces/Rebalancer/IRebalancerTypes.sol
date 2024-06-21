// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IUsdnProtocolTypes } from "../UsdnProtocol/IUsdnProtocolTypes.sol";

interface IRebalancerTypes {
    /**
     * @notice The deposit data of a user
     * @dev A value of zero for the `initiateTimestamp` indicates that the deposit or withdrawal was validated
     * @param initiateTimestamp Timestamp when the deposit or withdrawal was initiated
     * @param amount The amount of assets the user deposited
     * @param entryPositionVersion The position version the user entered at
     */
    struct UserDeposit {
        uint40 initiateTimestamp;
        uint88 amount; // Max 309'485'009 tokens with 18 decimals
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
        IUsdnProtocolTypes.PositionId id;
    }

    /**
     * @notice The parameters related to the validation process of the Rebalancer deposit/withdraw
     * @dev If the `validationDeadline` has passed, the user is blocked from interacting until the cooldown duration
     * has elapsed (since the moment of the initiate action). After the cooldown, in case of a deposit action, the user
     * must withdraw their funds with `resetDepositAssets`. After the cooldown, in case of a withdrawal action, the user
     * can initiate a new withdrawal again
     * @param validationDelay Minimum duration in seconds between an initiate action and the corresponding validate
     * action
     * @param validationDeadline Maximum duration in seconds between an initiate action and the corresponding validate
     * action
     * @param actionCooldown Duration from the initiate action during which the user can't interact with the Rebalancer
     * if the `validationDeadline` elapsed.
     */
    struct TimeLimits {
        uint80 validationDelay;
        uint80 validationDeadline;
        uint80 actionCooldown;
    }
}
