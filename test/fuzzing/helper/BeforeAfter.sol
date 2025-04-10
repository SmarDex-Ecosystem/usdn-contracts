// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { IUsdnProtocolHandler } from "../mocks/interfaces/IUsdnProtocolHandler.sol";
import { FuzzStructs } from "./FuzzStructs.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/* solhint-disable numcast/safe-cast */
/**
 * @notice BeforeAfter State Snapshot Contract
 * @dev  This abstract contract is used to snapshot and compare the protocol state
 */
abstract contract BeforeAfter is FuzzStructs {
    mapping(uint8 => State) states;

    struct State {
        mapping(address => ActorStates) actorStates;
        uint64 securityDeposit;
        uint256 usdnTotalSupply;
        bool positionsLiquidatable;
        bool positionWasLiqidatedInTheMeanwhile;
        address liquidator;
        uint256 liquidationRewards;
        bool feeCollectorCallbackTriggered;
        uint256 addedFees;
        uint256 feeCollectorBalance;
        Types.LiqTickInfo[] liqTicksInfo;
        int24 latestLiquidatedTick;
        int24 latestPositionTIck;
        int256 positionProfit;
        bool liquidationPending;
        bool positionsAboveHighestTickExist;
        int24 highestActualTick;
        uint256 divisor;
        uint256 vaultBalance;
        int256 pendingVaultBalance;
        uint256 balanceLong;
        uint256 pendingProtocolFee;
        int256 lastFunding;
        uint256 pendingActionsLength;
        uint256 usersTotalPendingActions;
        bool otherUsersPendingActions;
        uint256 tradingExpo;
        uint256 totalExpo;
        uint256 totalLongPositions;
        bool hasLowLeveragePositions;
        uint256 lowLeveragePositionsCount;
        uint256 unadjustedPrice;
        bool rebalancerTriggered;
        uint256 withdrawAssetToTransferAfterFees;
    }

    struct ActorStates {
        uint256 ethBalance;
        uint256 usdnShares;
        uint256 wstETHBalance;
        uint256 sdexBalance;
        Types.PendingAction pendingAction;
    }

    function _before(address[] memory actors) internal {
        fullReset();
        _setStates(0, actors);
    }

    function _after(address[] memory actors) internal {
        _setStates(1, actors);
    }

    function fullReset() internal {
        delete states[0];
        delete states[1];
    }

    function _setStates(uint8 callNum, address[] memory actors) internal {
        //First, set global states
        getSecurityDeposit(callNum);
        getTotalSupply(callNum);
        checkForLiquidatablePositions(callNum);
        checkForLiquidatorAndReward(callNum);
        checkForLiquidatedTicks(callNum);
        checkLatestPositionTick(callNum);
        getFeeCollectorBalance(callNum);
        checkForPositionProfit(callNum);
        checkForHighestActualTick(callNum);
        checkForWithdrawalAmount(callNum);
        getDivisor(callNum);
        getVaultBalance(callNum);
        getLongBalance(callNum);
        getPendingFee(callNum);
        getLastFunding(callNum);
        getPendingAcitonsLength(callNum);
        checkOtherUsersPendingActions(callNum, currentActor);
        getExpo(callNum);
        snapTotalLongPositions(callNum);
        getPositionsLeverage(callNum);
        checkUnadjustedPrice(callNum);
        checkIfRebalancerWasTriggered(callNum);

        //Second, set states per actor
        for (uint256 i = 0; i < actors.length; i++) {
            _setActorState(callNum, actors[i]);
        }
        //Third, set protocol address state
        _setActorState(callNum, address(usdnProtocol));
    }

    function _setActorState(uint8 callNum, address actor) internal {
        getBalances(callNum, actor);
        getPendingAcitons(callNum, actor);
    }

    function addCollectedFees(uint256 feeAmount) public {
        require(msg.sender == address(feeCollector), "FeeCollector calls only");
        states[1].feeCollectorCallbackTriggered = true;
        states[1].addedFees = feeAmount;
    }

    function getBalances(uint8 callNum, address user) internal {
        states[callNum].actorStates[user].ethBalance = user.balance;
        states[callNum].actorStates[user].usdnShares = usdn.sharesOf(user);
        states[callNum].actorStates[user].wstETHBalance = wstETH.balanceOf(user);
        states[callNum].actorStates[user].sdexBalance = sdex.balanceOf(user);
    }

    function getSecurityDeposit(uint8 callNum) internal {
        states[callNum].securityDeposit = usdnProtocol.getSecurityDepositValue();
    }

    function getTotalSupply(uint8 callNum) internal {
        states[callNum].usdnTotalSupply = usdn.totalSupply();
    }

    function getPendingAcitons(uint8 callNum, address user) internal {
        states[callNum].actorStates[user].pendingAction = usdnProtocol.getUserPendingAction(user);
    }

    function checkForLiquidatablePositions(uint8 callNum) internal {
        (bool success, bytes memory returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(
                IUsdnProtocolHandler.checkForLiquidations.selector,
                (createProtocolPrice() * wstETH.stEthPerToken()) / 1e18
            )
        );

        fl.t(success, "Static check for liquidatable positions failed");

        states[callNum].positionsLiquidatable = abi.decode(returnData, (bool));

        (success, returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(
                IUsdnProtocolHandler.checkForLiquidationsInActions.selector,
                (createProtocolPrice() * wstETH.stEthPerToken()) / 1e18
            )
        );

        fl.t(success, "Second check for liquidatable positions failed");

        states[callNum].positionWasLiqidatedInTheMeanwhile = abi.decode(returnData, (bool));

        (success, returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolHandler.checkForLiquidationPending.selector));

        fl.t(success, "Check for liquidation pending failed");

        states[callNum].liquidationPending = abi.decode(returnData, (bool));
    }

    function checkIfRebalancerWasTriggered(uint8 callNum) internal {
        (bool success, bytes memory returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolHandler.checkIfRebalancerTriggered.selector));

        fl.t(success, "Check for rebalancer trigger  failed");

        states[callNum].rebalancerTriggered = abi.decode(returnData, (bool));
    }

    function checkForLiquidatorAndReward(uint8 callNum) internal {
        (bool success, bytes memory returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolHandler.checkForLiquidatorAddressAndReward.selector)
        );

        fl.t(success, "Static check for liquidator and reward failed");

        (states[callNum].liquidator, states[callNum].liquidationRewards) = abi.decode(returnData, (address, uint256));
    }

    function checkForLiquidatedTicks(uint8 callNum) internal {
        (bool success, bytes memory returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolHandler.checkLiquidatedTicks.selector));

        fl.t(success, "Static check for liquidated ticks failed");

        (states[callNum].latestLiquidatedTick) = abi.decode(returnData, (int24));
    }

    function checkLatestPositionTick(uint8 callNum) internal {
        (bool success, bytes memory returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolHandler.checkLatestPositionTick.selector));

        fl.t(success, "Static check for position tick failed");

        (states[callNum].latestPositionTIck) = abi.decode(returnData, (int24));
    }

    function checkForPositionProfit(uint8 callNum) internal {
        (bool success, bytes memory returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolHandler.checkForPositionProfit.selector));

        fl.t(success, "Static check for position profit failed");

        (states[callNum].positionProfit) = abi.decode(returnData, (int256));
    }

    function checkForWithdrawalAmount(uint8 callNum) internal {
        (bool success, bytes memory returnData) =
            address(usdnProtocol).call(abi.encodeWithSelector(IUsdnProtocolHandler.checkWithdrawalAmount.selector));

        fl.t(success, "Static check for withdrawal amount failed");

        (states[callNum].withdrawAssetToTransferAfterFees) = abi.decode(returnData, (uint256));
    }

    function getDivisor(uint8 callNum) internal {
        states[callNum].divisor = usdn.divisor();
    }

    function getFeeCollectorBalance(uint8 callNum) internal {
        states[callNum].feeCollectorBalance = wstETH.balanceOf(address(feeCollector));
    }

    function getVaultBalance(uint8 callNum) internal {
        (, bytes memory returnData) = _getBalanceVaultCall();

        (states[callNum].vaultBalance) = abi.decode(returnData, (uint256));
        (states[callNum].pendingVaultBalance) = usdnProtocol.getPendingBalanceVault();
    }

    function getLongBalance(uint8 callNum) internal {
        (, bytes memory returnData) = _getBalanceLongCall();

        (states[callNum].balanceLong) = abi.decode(returnData, (uint256));
    }

    function getPendingFee(uint8 callNum) internal {
        (states[callNum].pendingProtocolFee) = usdnProtocol.getPendingProtocolFee();
    }

    function getLastFunding(uint8 callNum) internal {
        (, bytes memory returnData) = _getLastFundingPerDayCall();

        int256 lasFundingValue = abi.decode(returnData, (int256));

        if (lasFundingValue != 0) {
            lastFundingSwitch = true;
        }

        (states[callNum].lastFunding) = lasFundingValue;
    }

    function snapTotalLongPositions(uint8 callNum) internal {
        states[callNum].totalLongPositions = usdnProtocol.getTotalLongPositions();
    }

    function checkForHighestActualTick(uint8 callNum) internal {
        uint256 bitmapIndex = usdnProtocol.findLastSetInTickBitmap(usdnProtocol.getMaxTick());
        if (bitmapIndex != type(uint256).max) {
            // found a populated tick
            int24 highestActualTick = usdnProtocol.i_calcTickFromBitmapIndex(bitmapIndex);

            // Verify this is actually populated
            (bytes32 tickHash,) = usdnProtocol.getTickHash(highestActualTick);
            Types.TickData memory tickData = usdnProtocol.getTickData(tickHash);

            if (tickData.totalPos > 0) {
                states[callNum].highestActualTick = highestActualTick;
            }
        } else {
            ///here we have no positions
        }
    }

    function getPendingAcitonsLength(uint8 callNum) internal {
        uint256 totalPending;
        for (uint256 i = 0; i < USERS.length; i++) {
            Types.PendingAction memory action = usdnProtocol.getUserPendingAction(USERS[i]);
            if (action.action != Types.ProtocolAction.None) {
                totalPending++;
            }
        }
        states[callNum].usersTotalPendingActions = totalPending;

        (bool success, bytes memory returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(usdnProtocol.getActionablePendingActions.selector, address(1), 0, 100)
        );

        fl.t(success, "getPendingActionsLength call failed");

        // Decode the returned data which contains both actions array and another value
        (Types.PendingAction[] memory actions,) = abi.decode(returnData, (Types.PendingAction[], uint128[]));

        states[callNum].pendingActionsLength = actions.length;
    }

    function checkOtherUsersPendingActions(uint8 callNum, address user) internal returns (bool) {
        for (uint256 i = 0; i < USERS.length; i++) {
            if (USERS[i] == user) {
                continue;
            }

            Types.PendingAction memory action = usdnProtocol.getUserPendingAction(USERS[i]);
            if (action.action != Types.ProtocolAction.None) {
                states[callNum].otherUsersPendingActions = true;
                return true;
            }
        }
        return false;
    }

    function getExpo(uint8 callNum) internal {
        // Get trading expo
        (bool success1, bytes memory returnData1) = address(usdnProtocol).call(
            abi.encodeWithSelector(IUsdnProtocolHandler.getLongTradingExpo.selector, uint128(createProtocolPrice()))
        );

        fl.t(success1, "getLongTradingExpo call failed");

        states[callNum].tradingExpo = abi.decode(returnData1, (uint256));

        // Get total expo
        (bool success2, bytes memory returnData2) =
            address(usdnProtocol).call(abi.encodeWithSelector(usdnProtocol.getTotalExpo.selector));

        fl.t(success2, "getTotalExpo call failed");

        states[callNum].totalExpo = abi.decode(returnData2, (uint256));
    }

    function getPositionsLeverage(uint8 callNum) internal {
        if (positionIds.length == 0) {
            states[callNum].hasLowLeveragePositions = false;
            states[callNum].lowLeveragePositionsCount = 0;
            return;
        }

        uint256 lowLeverageCount = 0;
        bool hasLowLeveragePositions = false;
        Types.PositionId[] memory lowLeveragePositions = new Types.PositionId[](positionIds.length);

        for (uint256 i = 0; i < positionIds.length; i++) {
            (, uint256 version) = usdnProtocol.i_tickHash(positionIds[i].tick);

            if (positionIds[i].tickVersion != version) {
                continue;
            }
            (bool success, bytes memory returnData) = address(usdnProtocol).call(
                abi.encodeWithSelector(usdnProtocol.getLongPosition.selector, positionIds[i])
            );

            fl.t(success, "Getting position failed");

            (Types.Position memory position,) = abi.decode(returnData, (Types.Position, uint24));

            if (position.amount != 0 && (((uint256(position.totalExpo) * 1e21) / uint256(position.amount))) < 1e21) {
                lowLeveragePositions[lowLeverageCount] = positionIds[i];
                lowLeverageCount++;
                hasLowLeveragePositions = true;
            }
        }

        // Only at the end, update the state
        states[callNum].hasLowLeveragePositions = hasLowLeveragePositions;
        states[callNum].lowLeveragePositionsCount = lowLeverageCount;
    }

    function checkUnadjustedPrice(uint8 callNum) internal {
        (bool success, bytes memory returnData) = address(usdnProtocol).call(
            abi.encodeWithSelector(
                IUsdnProtocolHandler.i_unadjustPrice.selector,
                createProtocolPrice(),
                createProtocolPrice(),
                states[callNum].tradingExpo,
                usdnProtocol.getLiqMultiplierAccumulator()
            )
        );

        fl.t(success, "Getting unadjustedPrice failed");

        states[callNum].unadjustedPrice = abi.decode(returnData, (uint256));
    }

    /*
     * GLOBAL HELPERS
     */
    function createProtocolPrice() internal view returns (uint256) {
        (, int256 currentPrice,,,) = chainlink.latestRoundData();

        return (uint256(int256(currentPrice)) * 10 ** wstEthOracleMiddleware.getDecimals())
            / 10 ** wstEthOracleMiddleware.getChainlinkDecimals(); //same as Pyth
    }

    function createPythData() internal view returns (bytes memory currentPriceData) {
        (, int256 currentPrice,,,) = chainlink.latestRoundData();

        return abi.encodePacked(bytes(hex"504e4155"), uint256(currentPrice), uint64(block.timestamp - 1), uint64(0));
        //NOTE: confidence also hardcoded as 0 in a FuzzAdmin.sol::setPythPrice
    }
}
