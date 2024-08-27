// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";

import { ADMIN, USER_1, USER_2 } from "../utils/Constants.sol";
import { FuzzingSuite } from "./FuzzingSuite.sol";

contract FoundryFuzzingTest is Test {
    FuzzingSuite public fuzzingSuite;

    function setUp() public {
        fuzzingSuite = new FuzzingSuite();

        targetContract(address(fuzzingSuite));

        bytes4[] memory fuzzingSuiteSelectors = new bytes4[](37);
        //FuzzAction.sol
        fuzzingSuiteSelectors[0] = fuzzingSuite.initiateDeposit.selector;
        fuzzingSuiteSelectors[1] = fuzzingSuite.initiateWithdrawal.selector;
        fuzzingSuiteSelectors[2] = fuzzingSuite.initiateOpenPosition.selector;
        fuzzingSuiteSelectors[3] = fuzzingSuite.initiateClosePosition.selector;
        fuzzingSuiteSelectors[4] = fuzzingSuite.validateDeposit.selector;
        fuzzingSuiteSelectors[5] = fuzzingSuite.validateWithdrawal.selector;
        fuzzingSuiteSelectors[6] = fuzzingSuite.validateOpenPosition.selector;
        fuzzingSuiteSelectors[7] = fuzzingSuite.validateClosePosition.selector;
        fuzzingSuiteSelectors[8] = fuzzingSuite.validatePendingActions.selector;
        fuzzingSuiteSelectors[9] = fuzzingSuite.fullDeposit.selector;
        fuzzingSuiteSelectors[10] = fuzzingSuite.fullWithdrawal.selector;
        fuzzingSuiteSelectors[11] = fuzzingSuite.fullOpenPosition.selector;
        fuzzingSuiteSelectors[12] = fuzzingSuite.fullClosePosition.selector;
        fuzzingSuiteSelectors[13] = fuzzingSuite.liquidate.selector;

        //FuzzSetup.sol
        fuzzingSuiteSelectors[14] = fuzzingSuite.initializeUsdnProtocol.selector;

        //FuzzActionsAdmin.sol
        fuzzingSuiteSelectors[15] = fuzzingSuite.setMinLeverage.selector;
        fuzzingSuiteSelectors[16] = fuzzingSuite.setMaxLeverage.selector;
        fuzzingSuiteSelectors[17] = fuzzingSuite.setValidationDeadline.selector;
        fuzzingSuiteSelectors[18] = fuzzingSuite.setLiquidationPenalty.selector;
        fuzzingSuiteSelectors[19] = fuzzingSuite.setSafetyMarginBps.selector;
        fuzzingSuiteSelectors[20] = fuzzingSuite.setLiquidationIteration.selector;
        fuzzingSuiteSelectors[21] = fuzzingSuite.setEMAPeriod.selector;
        fuzzingSuiteSelectors[22] = fuzzingSuite.setFundingSF.selector;
        fuzzingSuiteSelectors[23] = fuzzingSuite.setProtocolFeeBps.selector;
        fuzzingSuiteSelectors[24] = fuzzingSuite.setPositionFeeBps.selector;
        fuzzingSuiteSelectors[25] = fuzzingSuite.setVaultFeeBps.selector;
        fuzzingSuiteSelectors[26] = fuzzingSuite.setRebalancerBonusBps.selector;
        fuzzingSuiteSelectors[27] = fuzzingSuite.setSdexBurnOnDepositRatio.selector;
        fuzzingSuiteSelectors[28] = fuzzingSuite.setSecurityDepositValue.selector;
        fuzzingSuiteSelectors[29] = fuzzingSuite.setFeeThreshold.selector;
        fuzzingSuiteSelectors[30] = fuzzingSuite.setFeeCollector.selector;
        fuzzingSuiteSelectors[31] = fuzzingSuite.setExpoImbalanceLimits.selector;
        fuzzingSuiteSelectors[32] = fuzzingSuite.setTargetUsdnPrice.selector;
        fuzzingSuiteSelectors[33] = fuzzingSuite.setUsdnRebaseThreshold.selector;
        fuzzingSuiteSelectors[34] = fuzzingSuite.setUsdnRebaseInterval.selector;
        fuzzingSuiteSelectors[35] = fuzzingSuite.setMinLongPosition.selector;

        //FuzzTransfer.sol
        fuzzingSuiteSelectors[36] = fuzzingSuite.transfer.selector;

        targetSelector(FuzzSelector({ addr: address(fuzzingSuite), selectors: fuzzingSuiteSelectors }));

        targetSender(USER_1);
        targetSender(USER_2);
        targetSender(ADMIN);
    }

    /// forge-config: ci.invariant.fail-on-revert = false
    /// forge-config: local.invariant.fail-on-revert = false
    function invariant_test() external { }
}
