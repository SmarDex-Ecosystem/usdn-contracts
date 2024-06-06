// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

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
}
