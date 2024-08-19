// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { USER_1, USER_2, USER_3 } from "../utils/Constants.sol";
import { FuzzingSuite } from "./FuzzingSuite.sol";
import { Test } from "forge-std/Test.sol";

contract FoundryFuzzingTest is Test {
    FuzzingSuite public fuzzingSuite;

    function setUp() public {
        fuzzingSuite = new FuzzingSuite();

        //        targetContract(address(fuzzingSuite));
        //
        //        bytes4[] memory fuzzingSuiteSelectors = new bytes4[](14);
        //        fuzzingSuiteSelectors[0] = fuzzingSuite.initiateDeposit.selector;
        //        fuzzingSuiteSelectors[1] = fuzzingSuite.initiateWithdrawal.selector;
        //        fuzzingSuiteSelectors[2] = fuzzingSuite.initiateOpenPosition.selector;
        //        fuzzingSuiteSelectors[3] = fuzzingSuite.initiateClosePosition.selector;
        //        fuzzingSuiteSelectors[4] = fuzzingSuite.validateDeposit.selector;
        //        fuzzingSuiteSelectors[5] = fuzzingSuite.validateWithdrawal.selector;
        //        fuzzingSuiteSelectors[6] = fuzzingSuite.validateOpenPosition.selector;
        //        fuzzingSuiteSelectors[7] = fuzzingSuite.validateClosePosition.selector;
        //        fuzzingSuiteSelectors[8] = fuzzingSuite.validatePendingActions.selector;
        //        fuzzingSuiteSelectors[9] = fuzzingSuite.fullDeposit.selector;
        //        fuzzingSuiteSelectors[10] = fuzzingSuite.fullWithdrawal.selector;
        //        fuzzingSuiteSelectors[11] = fuzzingSuite.fullOpenPosition.selector;
        //        fuzzingSuiteSelectors[12] = fuzzingSuite.fullClosePosition.selector;
        //        fuzzingSuiteSelectors[13] = fuzzingSuite.initializeUsdnProtocol.selector;

        //        targetSelector(
        //            FuzzSelector({
        //                addr: address(fuzzingSuite),
        //                selectors: fuzzingSuiteSelectors
        //            })
        //        );

        targetSender(USER_1);
        targetSender(USER_2);
        targetSender(USER_3);
    }

    function invariant_test() external { }
}
