// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the {_validateClosePositionWithAction} internal function
 * @custom:given A initiated protocol
 * @custom:and A pending close position action
 */
contract TestUsdnProtocolValidateClosePositionWithAction is UsdnProtocolBaseFixture {
    uint128 private constant POSITION_AMOUNT = 5 ether;
    PendingAction private pendingAction;
    uint128 private liqPriceWithoutPenalty;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        wstETH.mintAndApprove(address(this), 100 ether, address(protocol), type(uint256).max);

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: POSITION_AMOUNT,
                desiredLiqPrice: params.initialPrice / 4,
                price: params.initialPrice
            })
        );
        liqPriceWithoutPenalty = protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick));

        (pendingAction,) = protocol.i_getPendingAction(address(this));
    }

    /**
     * @custom:scenario Validate a close position action with enough funds in the vault
     * @custom:given A pending close position action
     * @custom:when The function _validateClosePositionWithAction is called with the correct values
     * @custom:then The action should be validated
     * @custom:and The position should not be liquidated
     * @custom:and The vault balance should be 0
     */
    function test_validateClosePositionWithActionEnoughInVault() public {
        int256 value = protocol.i_positionValue(params.initialPrice, liqPriceWithoutPenalty, POSITION_AMOUNT);
        assertTrue(value > 0, "Position value should be positive");

        (bool isValidated_, bool liquidated_) =
            protocol.i_validateClosePositionWithAction(pendingAction, abi.encode(params.initialPrice * 1000));

        assertTrue(isValidated_, "Action should be validated");
        assertFalse(liquidated_, "Position should not be liquidated");
        assertEq(protocol.getBalanceVault(), 0, "Vault balance should be 0");
    }
}
