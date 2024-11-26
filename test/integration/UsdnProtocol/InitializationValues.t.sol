// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary } from "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { TickMath } from "../../../src/libraries/TickMath.sol";

/**
 * @custom:feature Checking different values for the protocol initialization
 * @custom:background Given a forked ethereum mainnet chain
 */
contract TestForkUsdnProtocolInitializationValues is UsdnProtocolBaseIntegrationFixture {
    /* 
        Test results:
            200 wsteth:
                - max leverage:
                    -  collateral   2 wsteth (min long position)
                    -  leverage     ~x4.9
                - min leverage:
                    - collateral    ~8.9 wsteth
                    - leverage      x1.1

            300 wsteth:
                - max leverage:
                    - collateral    2 wsteth (min long position)
                    - leverage      ~x7.4
                - min leverage:
                    - collateral    ~13.4 wsteth
                    - leverage      x1.1
     */

    /**
     * @dev The type of leverage to use in the {_setupLongPositions} function
     * @param min Uses the {_minLeverage} with the maximum position collateral
     * @param max Uses the maximum position leverage possible with the {_minLongPosition} collateral
     */
    enum LeverageType {
        min,
        max
    }

    uint128 internal constant WORSE_INITIAL_AMOUNT = 200 ether;
    uint128 internal constant OPTIMISTIC_INITIAL_AMOUNT = 300 ether;
    uint128 internal constant MAX_LONG_AMOUNT = 500 ether;

    /**
     * @custom:scenario A user open a position with a minimum leverage
     * @custom:given A usdn protocol is initiated with the worse initial amount
     * @custom:when The function {initiateOpenPosition} is called
     * @custom:then The user position should be initiated
     */
    function test_initializeWorseInitialAmountMinLeverage() external {
        _setupLongPositions(WORSE_INITIAL_AMOUNT, LeverageType.min);
    }

    /**
     * @custom:scenario A user open a position with a maximum leverage
     * @custom:given A usdn protocol is initiated with the worse initial amount
     * @custom:when The function {initiateOpenPosition} is called
     * @custom:then The user position should be initiated
     */
    function test_initializeWorseInitialAmountMaxLeverage() external {
        _setupLongPositions(WORSE_INITIAL_AMOUNT, LeverageType.max);
    }

    /**
     * @custom:scenario A user open a position with a minimum leverage
     * @custom:given A usdn protocol is initiated with the optimistic initial amount
     * @custom:when The function {initiateOpenPosition} is called
     * @custom:then The user position should be initiated
     */
    function test_initializeOptimisticInitialAmountMinLeverage() external {
        _setupLongPositions(OPTIMISTIC_INITIAL_AMOUNT, LeverageType.min);
    }

    /**
     * @custom:scenario A user open a position with a maximum leverage
     * @custom:given A usdn protocol is initiated with the optimistic initial amount
     * @custom:when The function {initiateOpenPosition} is called
     * @custom:then The user position should be initiated
     */
    function test_initializeOptimisticInitialAmountMaxLeverage() external {
        _setupLongPositions(OPTIMISTIC_INITIAL_AMOUNT, LeverageType.max);
    }

    /**
     * @notice Deploy the usdn protocol with the initial long amount and fill it with a position close to the imbalance
     * limit according to the type of leverage
     * @param initialLongAmount The initial long amount used during the protocol initialization
     * @param leverageType The type of leverage. If {min} uses the {_minLeverage}, if {max} uses the
     * {_minLongPosition} with the highest possible leverage
     */
    function _setupLongPositions(uint128 initialLongAmount, LeverageType leverageType) internal {
        if (initialLongAmount == WORSE_INITIAL_AMOUNT) {
            emit log_named_decimal_uint("WORSE AMOUNT", WORSE_INITIAL_AMOUNT, 18);
        } else if (initialLongAmount == OPTIMISTIC_INITIAL_AMOUNT) {
            emit log_named_decimal_uint("OPTIMISTIC AMOUNT", OPTIMISTIC_INITIAL_AMOUNT, 18);
        }

        params = DEFAULT_PARAMS;
        params.initialLong = initialLongAmount;

        _setUp(params);

        (bool success,) = address(wstETH).call{ value: MAX_LONG_AMOUNT }("");
        assertTrue(success, "wsteth transfer error");
        wstETH.approve(address(protocol), type(uint256).max);

        uint256 maxTotalExpoToFill = FixedPointMathLib.fullMulDiv(
            uint256(protocol.getOpenExpoImbalanceLimitBps()),
            protocol.getBalanceVault(),
            UsdnProtocolConstantsLibrary.BPS_DIVISOR
        );

        uint256 leverageFactor = 10 ** UsdnProtocolConstantsLibrary.LEVERAGE_DECIMALS;
        uint256 ligPriceWithoutPenalty;
        uint128 longPosition;
        uint256 leverage;
        uint256 minLongPosition = protocol.getMinLongPosition();
        if (leverageType == LeverageType.min) {
            leverage = protocol.getMinLeverage();
            ligPriceWithoutPenalty =
                params.initialPrice - FixedPointMathLib.fullMulDiv(leverageFactor, params.initialPrice, leverage);
            longPosition = uint128(FixedPointMathLib.fullMulDiv(leverageFactor, maxTotalExpoToFill, leverage));

            emit log_named_decimal_uint("MIN LEVERAGE", leverage, UsdnProtocolConstantsLibrary.LEVERAGE_DECIMALS);
        } else if (leverageType == LeverageType.max) {
            longPosition = uint128(minLongPosition);
            leverage = uint128(FixedPointMathLib.fullMulDiv(leverageFactor, maxTotalExpoToFill, longPosition));
            ligPriceWithoutPenalty =
                params.initialPrice - FixedPointMathLib.fullMulDiv(leverageFactor, params.initialPrice, leverage);
            emit log_named_decimal_uint("MAX LEVERAGE", leverage, UsdnProtocolConstantsLibrary.LEVERAGE_DECIMALS);
        }
        uint256 maxLeverage = protocol.getMaxLeverage();
        assertLe(leverage, maxLeverage, "Leverage should be lower or equal than max leverage");
        assertGe(longPosition, minLongPosition, "Position should be higher or equal than minimum long position");

        uint128 liqPrice = uint128(
            TickMath.getPriceAtTick(
                TickMath.getTickAtPrice(ligPriceWithoutPenalty) + protocol.getTickSpacing()
                    + int24(protocol.getLiquidationPenalty())
            )
        );

        protocol.initiateOpenPosition{ value: protocol.getSecurityDepositValue() }(
            longPosition,
            liqPrice,
            type(uint128).max,
            maxLeverage,
            address(this),
            payable(this),
            type(uint256).max,
            "",
            EMPTY_PREVIOUS_DATA
        );

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        assertTrue(action.action == ProtocolAction.ValidateOpenPosition, "The action type is wrong");

        emit log_named_decimal_uint("LONG POSITION", longPosition, 18);
    }

    receive() external payable { }
}
