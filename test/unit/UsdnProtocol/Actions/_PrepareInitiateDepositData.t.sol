// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolActionsVaultLibrary as ActionsVault } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsVaultLibrary.sol";

/**
 * @custom:feature Test of the protocol `_prepareInitiateDepositData` internal function
 * @custom:background Given a protocol with SDEX burn on deposit setting enabled
 */
contract TestUsdnProtocolActionsPrepareInitiateDepositData is UsdnProtocolBaseFixture {
    uint128 private constant POSITION_AMOUNT = 1 ether;
    bytes private currentPriceData;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialPrice = 1 ether;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);

        currentPriceData = abi.encode(params.initialPrice);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Reverts                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario Call _prepareInitiateDepositData with an amount so low that it would mint 0 USDN
     * @custom:given There is a vault fee
     * @custom:when _prepareInitiateDepositData is called with a deposit of 1 wei
     * @custom:then The call reverts with an UsdnProtocolDepositTooSmall error
     */
    function test_RevertWhen_prepareInitiateDepositDataWithUSDNAmountMintedTooSmall() public {
        vm.prank(ADMIN);
        protocol.setVaultFeeBps(1);
        vm.expectRevert(UsdnProtocolDepositTooSmall.selector);
        protocol.i_prepareInitiateDepositData(address(this), 1, abi.encode(1 ether));
    }

    /**
     * @custom:scenario Call _prepareInitiateDepositData with an amount so low that it would burn 0 SDEX
     * @custom:when _prepareInitiateDepositData is called with amount = (burnRatioDivisor / burnRatio - 1)
     * @custom:then The call reverts with an UsdnProtocolDepositTooSmall error
     */
    function test_RevertWhen_prepareInitiateDepositDataWithSDEXAmountBurnedTooSmall() public {
        uint32 burnRatio = protocol.getSdexBurnOnDepositRatio();
        uint256 burnRatioDivisor = protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR();

        // calculate the amount of usdn to mint to burn 1 wei of SDEX
        uint128 usdnAmountToMint = uint128(burnRatioDivisor / burnRatio);

        vm.expectRevert(UsdnProtocolDepositTooSmall.selector);
        protocol.i_prepareInitiateDepositData(address(this), usdnAmountToMint - 1, abi.encode(1 ether));
    }

    /* -------------------------------------------------------------------------- */
    /*                         _prepareInitiateDepositData                        */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario _prepareClosePositionData is called with POSITION_AMOUNT of assets to be deposited
     * @custom:when _prepareInitiateDepositData is called
     * @custom:then The matching data is returned
     * @custom:and There should be no pending liquidations
     */
    function test_prepareInitiateDepositData() public {
        ActionsVault.InitiateDepositData memory data =
            protocol.i_prepareInitiateDepositData(address(this), POSITION_AMOUNT, currentPriceData);

        assertFalse(data.isLiquidationPending, "There should be no pending liquidations");
        _assertData(data, false);
    }

    /**
     * @custom:scenario _prepareInitiateDepositData is called with 2 ticks that can be liquidated
     * @custom:given A current price below the second tick's liquidation price
     * @custom:and A high risk position that will be liquidated first
     * @custom:and A liquidation iterations setting at 1
     * @custom:when _prepareInitiateDepositData is called
     * @custom:then The matching data is returned
     * @custom:and Only the high risk position should have been liquidated
     * @custom:and The function should have returned early
     * @custom:and There should be pending liquidations
     */
    function test_prepareInitiateDepositDataWithPendingLiquidations() public {
        // open long positions to liquidate
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice * 9 / 10, // 10x leverage
                price: params.initialPrice
            })
        );
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice * 8 / 10, // 9x leverage
                price: params.initialPrice
            })
        );
        skip(30 minutes);

        vm.prank(ADMIN);
        protocol.setLiquidationIteration(1);

        currentPriceData = abi.encode(params.initialPrice * 7 / 10);

        ActionsVault.InitiateDepositData memory data =
            protocol.i_prepareInitiateDepositData(address(this), POSITION_AMOUNT, currentPriceData);

        assertTrue(data.isLiquidationPending, "There should be pending liquidations");
        _assertData(data, true);
    }

    /// @notice Assert the data in InitiateDepositData depending on `isEarlyReturn`
    function _assertData(ActionsVault.InitiateDepositData memory data, bool isEarlyReturn) private view {
        uint128 currentPrice = abi.decode(currentPriceData, (uint128));

        if (isEarlyReturn) {
            assertEq(data.feeBps, 0, "The fee should not be set");
            assertEq(data.totalExpo, 0, "The total expo should not be set");
            assertEq(data.balanceLong, 0, "The balance long should not be set");
            assertEq(data.balanceVault, 0, "The balance vault should not be set");
            assertEq(data.sdexToBurn, 0, "The amount of SDEX to burn should not be set");
        } else {
            (, uint256 sdexToBurn_) = protocol.previewDeposit(POSITION_AMOUNT, currentPrice, uint40(block.timestamp));

            assertEq(data.feeBps, protocol.getVaultFeeBps(), "The fee should be the one in the protocol");
            assertEq(data.totalExpo, protocol.getTotalExpo(), "The total expo should be the one in the protocol");
            assertEq(data.balanceLong, protocol.getBalanceLong(), "The balance long should be the one in the protocol");
            assertEq(
                data.balanceVault, protocol.getBalanceVault(), "The balance vault should be the one in the protocol"
            );
            assertGt(data.sdexToBurn, 0, "Sanity check: enable SDEX burn on deposit");
            assertEq(data.sdexToBurn, sdexToBurn_, "The amount of SDEX to burn should be the expected amount");
        }
    }
}
