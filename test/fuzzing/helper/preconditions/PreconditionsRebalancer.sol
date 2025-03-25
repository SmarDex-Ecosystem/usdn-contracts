// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./PreconditionsBase.sol";

/* solhint-disable numcast/safe-cast */

abstract contract PreconditionsRebalancer is PreconditionsBase {
    function initiateDepositAssetsPreconditions(uint88 amountSeed)
        internal
        returns (InitiateDepositAssetsParams memory params)
    {
        params.amount = uint88(fl.clamp(amountSeed, rebalancer.getMinAssetDeposit(), wstETH.balanceOf(currentActor)));
        params.to = currentActor;

        // Check if the user has an existing deposit
        IRebalancer.UserDeposit memory existingDeposit = rebalancer.getUserDepositData(params.to);
        require(existingDeposit.amount == 0 && existingDeposit.initiateTimestamp == 0, "Existing deposit found");

        return params;
    }

    function validateDepositAssetsPreconditions() internal returns (ValidateDepositAssetsParams memory params) {
        vm.warp(block.timestamp + 25 seconds);
        params.user = currentActor;

        IRebalancer.UserDeposit memory depositData = rebalancer.getUserDepositData(params.user);
        require(depositData.initiateTimestamp > 0, "No pending deposit");

        IRebalancer.TimeLimits memory timeLimits = rebalancer.getTimeLimits();

        vm.warp(block.timestamp + timeLimits.validationDelay);

        return params;
    }

    function resetDepositAssetsPreconditions() internal returns (ResetDepositAssetsParams memory params) {
        vm.warp(block.timestamp + 4 hours + 1); //NOTE: currently hardcoded

        params.user = currentActor;

        // IRebalancer.UserDeposit memory depositData = rebalancer.getUserDepositData(params.user);

        IRebalancer.TimeLimits memory timeLimits = rebalancer.getTimeLimits();

        vm.warp(block.timestamp + timeLimits.actionCooldown);

        return params;
    }

    function initiateWithdrawAssetsPreconditions() internal returns (InitiateWithdrawAssetsParams memory params) {
        params.user = currentActor;

        IRebalancer.UserDeposit memory depositData = rebalancer.getUserDepositData(params.user);
        require(depositData.entryPositionVersion > rebalancer.getPositionVersion(), "No valid deposit"); //skip invalid
            // runs

        if (depositData.initiateTimestamp > 0) {
            IRebalancer.TimeLimits memory timeLimits = rebalancer.getTimeLimits();
            vm.warp(block.timestamp + timeLimits.actionCooldown);
        }

        return params;
    }

    function validateWithdrawAssetsPreconditions(uint88 amountSeed)
        internal
        returns (ValidateWithdrawAssetsParams memory params)
    {
        vm.warp(block.timestamp + 25 seconds);

        params.user = currentActor;

        IRebalancer.UserDeposit memory depositData = rebalancer.getUserDepositData(params.user);

        IRebalancer.TimeLimits memory timeLimits = rebalancer.getTimeLimits();

        vm.warp(block.timestamp + timeLimits.validationDelay);

        params.amount = uint88(fl.clamp(amountSeed, 0, depositData.amount));

        return params;
    }

    function initiateClosePositionInRebalancerPreconditions(uint88 amountSeed)
        internal
        returns (InitiateClosePositionParamsInRebalancer memory params)
    {
        vm.warp(block.timestamp + 4 hours + 1); //NOTE: currently hardcoded

        params.user = currentActor;
        params.to = address(rebalancer);
        params.validator = payable(currentActor); //NOTE: currently hardcoded

        IRebalancer.UserDeposit memory depositData = rebalancer.getUserDepositData(params.user);

        require(depositData.amount > 0, "User has no deposits, skipping current run");

        // IRebalancer.PositionData memory positionData = rebalancer.getPositionData(rebalancer.getPositionVersion());

        params.amount = uint88(fl.clamp(amountSeed, 1, depositData.amount));
        params.userMinPrice = 0;
        params.deadline = type(uint256).max;

        params.txValue = totalValue();
        params.delegationData = new bytes(0); //NOTE: currently hardcoded

        (params.previousActionsData,, params.lastAction,) = getPreviousActionsData(currentActor, createProtocolPrice());

        return params;
    }
}
