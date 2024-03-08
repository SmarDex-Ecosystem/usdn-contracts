// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

/**
 * @custom:feature Fuzzing tests for internal functions of the protocol expo limits
 * @custom:background Given a protocol instance in balanced state with random expos
 */
contract TestUsdnProtocolFuzzingExpoLimits is UsdnProtocolBaseFixture {
    // the initial long expo
    uint256 internal initialLongExpo;
    // the initial vault expo
    uint256 internal initialVaultExpo;

    /**
     * @custom:scenario The `imbalanceLimitDeposit` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitDeposit` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitDeposit(uint128 initialDeposit, uint128 initialLong, uint256 depositAmount)
        public
    {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // range depositAmount properly
        depositAmount = bound(depositAmount, 1, type(uint128).max);
        // new vault expo
        uint256 newExpoVault = initialVaultExpo + depositAmount;
        // expected imbalance percentage
        uint256 imbalancePct =
            (newExpoVault - initialLongExpo) * uint256(protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR()) / initialLongExpo;

        // call `imbalanceLimitDeposit` with depositAmount
        if (imbalancePct >= uint256(protocol.getSoftVaultExpoImbalanceLimit())) {
            // should revert with above soft vault imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IUsdnProtocolErrors.UsdnProtocolSoftVaultImbalanceLimitReached.selector, imbalancePct
                )
            );
            protocol.i_imbalanceLimitDeposit(depositAmount);
        } else {
            // should not revert
            protocol.i_imbalanceLimitDeposit(depositAmount);
        }
    }

    /**
     * @custom:scenario The `imbalanceLimitWithdrawal` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitWithdrawal` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitWithdrawal(uint128 initialDeposit, uint128 initialLong, uint256 withdrawalAmount)
        public
    {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // range withdrawalAmount properly
        withdrawalAmount = bound(withdrawalAmount, 2, initialVaultExpo);
        // new vault expo
        uint256 newVaultExpo = initialVaultExpo - withdrawalAmount;
        // expected imbalance percentage
        int256 imbalancePct = (int256(initialLongExpo) - int256(newVaultExpo))
            * protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR() / int256(initialVaultExpo);

        // call `i_imbalanceLimitWithdrawal` with withdrawalAmount
        if (imbalancePct >= protocol.getHardLongExpoImbalanceLimit()) {
            // should revert with above hard long imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IUsdnProtocolErrors.UsdnProtocolHardLongImbalanceLimitReached.selector, imbalancePct
                )
            );
            protocol.i_imbalanceLimitWithdrawal(withdrawalAmount);
        } else {
            // should not revert
            protocol.i_imbalanceLimitWithdrawal(withdrawalAmount);
        }
    }

    /**
     * @custom:scenario The `imbalanceLimitOpen` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitOpen` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitOpen(uint128 initialDeposit, uint128 initialLong, uint256 openAmount) public {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // range withdrawalAmount properly
        openAmount = bound(openAmount, 1, type(uint128).max);
        // total expo to add
        uint256 totalExpoToAdd = openAmount * initialLongLeverage / 10 ** protocol.LEVERAGE_DECIMALS();
        // expected imbalance percentage
        int256 imbalancePct = (
            (int256(protocol.getTotalExpo() + totalExpoToAdd) - int256(protocol.getBalanceLong() + openAmount))
                - int256(initialVaultExpo)
        ) * protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR() / int256(initialVaultExpo);
        // call `i_imbalanceLimitWithdrawal` with withdrawalAmount
        if (imbalancePct >= protocol.getSoftLongExpoImbalanceLimit()) {
            // should revert with above soft long imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IUsdnProtocolErrors.UsdnProtocolSoftLongImbalanceLimitReached.selector, imbalancePct
                )
            );
            protocol.i_imbalanceLimitOpen(totalExpoToAdd, openAmount);
        } else {
            // should not revert
            protocol.i_imbalanceLimitOpen(totalExpoToAdd, openAmount);
        }
    }

    /**
     * @custom:scenario The `imbalanceLimitClose` should pass with still balanced amounts with state
     * and revert when amounts bring protocol out of limits
     * @custom:given The randomized expo balanced protocol state
     * @custom:when The `imbalanceLimitClose` is called with a random amount
     * @custom:then The transaction should revert in case imbalance or pass if still balanced
     */
    function testFuzz_imbalanceLimitClose(uint128 initialDeposit, uint128 initialLong, uint256 closeAmount) public {
        // initialize random balanced protocol
        _randInitBalanced(initialDeposit, initialLong);
        // current balance long
        uint256 currentBalanceLong = protocol.getBalanceLong();
        // range withdrawalAmount properly
        closeAmount = bound(closeAmount, 1, currentBalanceLong);
        // total expo to remove
        uint256 totalExpoToRemove = closeAmount * initialLongLeverage / 10 ** protocol.LEVERAGE_DECIMALS();
        // expected imbalance percentage
        int256 imbalancePct = (
            int256(initialVaultExpo)
                - (
                    (int256(protocol.getTotalExpo()) - int256(totalExpoToRemove))
                        - (int256(currentBalanceLong) - int256(closeAmount))
                )
        ) * protocol.EXPO_IMBALANCE_LIMIT_DENOMINATOR() / int256(initialLongExpo);
        // call `i_imbalanceLimitClose` with totalExpoToRemove and closeAmount
        if (imbalancePct >= protocol.getHardVaultExpoImbalanceLimit()) {
            // should revert with above hard vault imbalance limit
            vm.expectRevert(
                abi.encodeWithSelector(
                    IUsdnProtocolErrors.UsdnProtocolHardVaultImbalanceLimitReached.selector, imbalancePct
                )
            );
            protocol.i_imbalanceLimitClose(totalExpoToRemove, closeAmount);
        } else {
            // should not revert
            protocol.i_imbalanceLimitClose(totalExpoToRemove, closeAmount);
        }
    }

    /// @dev Calculate proper initial values to initiate a balanced protocol
    function _randInitBalanced(uint128 initialDeposit, uint128 initialLong) private {
        // cannot be less than 1 ether
        initialDeposit = uint128(bound(initialDeposit, uint128(1 ether), uint128(5000 ether)));
        // cannot be less than 1 ether
        initialLong = uint128(bound(initialLong, uint128(1 ether), uint128(5000 ether)));

        // initial default params
        SetUpParams memory params = DEFAULT_PARAMS;

        // min long expo to initiate a balanced protocol
        uint256 minLongExpo = initialDeposit - initialDeposit * 2 / 100;
        // max long expo to initiate a balanced protocol
        uint256 maxLongExpo = initialDeposit + initialDeposit * 2 / 100;
        // initial leverage
        uint128 initialLeverage = uint128(
            10 ** 21 * uint256(params.initialPrice) / (uint256(params.initialPrice) - uint256(params.initialPrice / 2))
        );

        /* 
            Retrieve long balance from long expo:
            ---------------------------------------------------------------
            
            totalExpo(TX) = LongExpo(LE) + LongBalance(LB)        
            totalExpo(TX) = LongBalance(LB) x leverage(l) / LeverageDecimal(LD)

            TX = LB . l / LD
            TX . LD = LB . l
            TX . LD / LB = l
            (LE + LB) . LD / LB = l
            (LE . LD / LB) + (LB . LD / LB) = l
            LE . LD / LB + LD  = l
            LE . LD / LB  = l - LD
            LB = LE . LD / (l - LD)
             
            LongBalance = (LongExpo x LeverageDecimal) / (leverage - LeverageDecimal)
        
            ---------------------------------------------------------------
         */

        // min long amount
        uint256 minLongAmount = uint128(uint256(minLongExpo) * 10 ** 21 / (uint256(initialLeverage) - 10 ** 21));
        // max long amount
        uint256 maxLongAmount = uint128(uint256(maxLongExpo) * 10 ** 21 / (uint256(initialLeverage) - 10 ** 21));

        // assign initial long amount in range min max
        initialLong = uint128(bound(minLongAmount, uint128(minLongAmount), uint128(maxLongAmount)));

        // calculation doesn't take count of min allowed by the protocol
        if (initialLong < 1 ether) {
            initialLong = 1 ether;
        }

        // assign initial values
        params.initialDeposit = initialDeposit;
        params.initialLong = initialLong;

        // init protocol
        super._setUp(params);

        // store initial expos
        initialLongExpo = protocol.getTotalExpo() - protocol.getBalanceLong();
        initialVaultExpo = protocol.getBalanceVault();
    }
}
