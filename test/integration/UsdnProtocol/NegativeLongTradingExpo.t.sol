// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { MOCK_PYTH_DATA } from "../../unit/Middlewares/utils/Constants.sol";
import { SET_PROTOCOL_PARAMS_MANAGER, USER_1 } from "../../utils/Constants.sol";
import { UsdnProtocolBaseIntegrationFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature Have the long trading expo being negative and check the state of the protocol
 * @custom:background The protocol is heavily imbalanced to allow for fundings to push the long trading expo below 0
 * @custom:and A small long position opened to accumulate fundings
 */
contract TestUsdnProtocolNegativeLongTradingExpo is UsdnProtocolBaseIntegrationFixture {
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(SafeTransferLib.PERMIT2);
    uint128 constant DEPOSIT_AMOUNT = 1 ether;
    uint256 oracleFee;
    uint256 securityDeposit;
    PositionId posIdToClose;
    uint128 amountInPosition = 2 ether;
    uint128 pythPrice;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);

        deal(address(wstETH), address(this), 1e6 ether);
        deal(address(sdex), address(this), 1e6 ether);
        wstETH.approve(address(protocol), type(uint256).max);
        sdex.approve(address(protocol), type(uint256).max);

        // disable imbalance checks to make it easier to have heavy fundings
        vm.prank(SET_PROTOCOL_PARAMS_MANAGER);
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0);
        oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.None);

        securityDeposit = protocol.getSecurityDepositValue();
        // deposit assets in the protocol to imbalance it heavily
        protocol.initiateDeposit{ value: securityDeposit }(
            100 ether, 0, address(this), payable(this), type(uint256).max, "", EMPTY_PREVIOUS_DATA
        );

        (, posIdToClose) = protocol.initiateOpenPosition{ value: securityDeposit + oracleFee }(
            amountInPosition,
            DEFAULT_PARAMS.initialPrice / 2,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            USER_1, // so we can have 2 initiates at the same time
            type(uint256).max,
            MOCK_PYTH_DATA,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();

        {
            uint128 ethPrice = uint128(wstETH.getWstETHByStETH(DEFAULT_PARAMS.initialPrice)) / 1e10;
            mockPyth.setConf(0);
            mockPyth.setPrice(int64(uint64(ethPrice)));
            mockPyth.setLastPublishTime(block.timestamp - 1);
            // the price returned by the oracle middleware
            pythPrice = uint128(wstETH.getStETHByWstETH(ethPrice) * 1e10) + 7_000_000_000;
        }

        oracleFee = oracleMiddleware.validationCost(MOCK_PYTH_DATA, ProtocolAction.ValidateDeposit);
        protocol.validateDeposit{ value: oracleFee }(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);
        protocol.validateOpenPosition{ value: oracleFee }(USER_1, MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        skip(5 days);

        // update the ema
        mockPyth.setLastPublishTime(block.timestamp - 1);
        protocol.liquidate{ value: oracleFee }(MOCK_PYTH_DATA);
    }

    /**
     * @custom:scenario The fundings can push the long trading expo at its limit and positions can still be closed
     * @custom:given Fundings accumulated until the protocol has the smallest trading expo possible
     * @custom:when The long position is closed at the exact same price
     * @custom:then The user receives value close to the position's total expo
     */
    function test_closePositionWithMinimumLongTradingExpo() public {
        skip(30 days);
        uint256 totalExpo = protocol.getTotalExpo();

        assertEq(
            protocol.longAssetAvailableWithFunding(DEFAULT_PARAMS.initialPrice, uint128(block.timestamp)),
            totalExpo * (BPS_DIVISOR - Constants.MIN_LONG_TRADING_EXPO_BPS) / BPS_DIVISOR,
            "sanity check: trading expo should be equal to the min trading expo for this test to work"
        );

        /* --------------------------- close the position --------------------------- */

        uint256 balanceOfBefore = wstETH.balanceOf(address(this));
        protocol.initiateClosePosition{ value: oracleFee + securityDeposit }(
            posIdToClose,
            amountInPosition,
            0,
            address(this),
            payable(this),
            type(uint256).max,
            MOCK_PYTH_DATA,
            EMPTY_PREVIOUS_DATA,
            ""
        );

        _waitDelay();
        mockPyth.setLastPublishTime(block.timestamp - 1);

        uint24 liquidationPenalty = protocol.getLiquidationPenalty();
        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));
        uint128 priceWithFees = uint128(pythPrice - pythPrice * protocol.getPositionFeeBps() / BPS_DIVISOR);
        uint256 assetToTransfer = uint256(
            protocol.i_positionValue(
                action.closePosTotalExpo,
                priceWithFees,
                protocol.i_getEffectivePriceForTick(
                    protocol.i_calcTickWithoutPenalty(posIdToClose.tick, liquidationPenalty), action.liqMultiplier
                )
            )
        );

        protocol.validateClosePosition{ value: oracleFee }(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);

        assertEq(
            balanceOfBefore + assetToTransfer,
            wstETH.balanceOf(address(this)),
            "User should have received the position value"
        );
    }

    /**
     * @custom:scenario The fundings can push the long trading expo at its limit and positions can still be opened
     * @custom:given Fundings accumulated until the protocol has the smallest trading expo possible
     * @custom:when A long position is opened
     * @custom:then It's value is close to it's collateral amount
     * @custom:when Time passes without the price changing
     * @custom:then It's value grows over time
     */
    function test_openAndClosePositionWithNegativeLongTradingExpo() public {
        skip(30 days);
        uint256 totalExpo = protocol.getTotalExpo();

        assertEq(
            protocol.longAssetAvailableWithFunding(DEFAULT_PARAMS.initialPrice, uint128(block.timestamp)),
            totalExpo * (BPS_DIVISOR - Constants.MIN_LONG_TRADING_EXPO_BPS) / BPS_DIVISOR,
            "sanity check: trading expo should be equal to the min trading expo for this test to work"
        );

        /* ------------------------------ open position ----------------------------- */

        uint128 priceWithFees = uint128(pythPrice - pythPrice * protocol.getPositionFeeBps() / BPS_DIVISOR);

        // Make sure we can open a position
        (, PositionId memory posId) = protocol.initiateOpenPosition{ value: securityDeposit + oracleFee }(
            2 ether,
            DEFAULT_PARAMS.initialPrice - (DEFAULT_PARAMS.initialPrice / 2),
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(this),
            type(uint256).max,
            MOCK_PYTH_DATA,
            EMPTY_PREVIOUS_DATA
        );

        _waitDelay();
        mockPyth.setLastPublishTime(block.timestamp - 1);

        protocol.validateOpenPosition{ value: oracleFee }(payable(this), MOCK_PYTH_DATA, EMPTY_PREVIOUS_DATA);
        assertApproxEqAbs(
            2 ether,
            protocol.getPositionValue(posId, priceWithFees, uint128(block.timestamp)),
            0.002 ether,
            "The position value should be very close to the collateral given"
        );
    }

    receive() external payable { }
}
