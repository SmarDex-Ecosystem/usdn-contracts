// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature The security deposit of the USDN Protocol
 * @custom:background Given a protocol initialized with default params
 * @custom:and A security deposit of 0.5 ether
 */
contract TestUsdnProtocolRefundSecurityDeposit is UsdnProtocolBaseFixture {
    uint64 internal SECURITY_DEPOSIT_VALUE;
    bytes priceData;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableSecurityDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1000 ether, address(protocol), type(uint256).max);
        priceData = abi.encode(params.initialPrice);

        SECURITY_DEPOSIT_VALUE = protocol.getSecurityDepositValue();
    }

    /**
     * @custom:scenario Refund security deposit after a position has been initiated and liquidated
     * @custom:given A deployed USDN protocol
     * @custom:when A long is initiated at a price of $2000 with a security deposit of 0.5 ether and a leverage of 10x
     * @custom:and The price drops to $1000 and the position is liquidated
     * @custom:then The validator calls `refundSecurityDeposit` for the position to get back the security deposit
     * @custom:and The security deposit is refunded
     */
    function test_refundSecurityDepositAfterLiquidation() public {
        _initiateAndLiquidate();

        // snapshot balances
        uint256 balanceBefore = address(this).balance;

        // refund the security deposit
        protocol.refundSecurityDeposit();

        assertEq(address(this).balance, balanceBefore + SECURITY_DEPOSIT_VALUE, "security deposit refunded");
    }

    /**
     * @custom:scenario A user tries to refund the security deposit without having a position liquidated
     * @custom:given A deployed USDN protocol
     * @custom:when A long is initiated at a price of $2000 with a security deposit of 0.5 ether and a leverage of 10x
     * @custom:then The user tries to call `refundSecurityDeposit` for the position
     * @custom:and The user gets an error
     */
    function test_failRefundSecurityDepositWithoutLiquidation() public {
        _initiateAndLiquidate();

        // snapshot balances
        uint256 balanceBefore = address(this).balance;

        // another user try to get a refund for his security deposit
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(IUsdnProtocolErrors.UsdnProtocolNotEligibleForRefund.selector));
        protocol.refundSecurityDeposit();

        assertEq(address(this).balance, balanceBefore, "security deposit not refunded");
    }

    function _initiateAndLiquidate() internal {
        // initiate a long position
        protocol.initiateOpenPosition{ value: SECURITY_DEPOSIT_VALUE }(
            5 ether,
            params.initialPrice * 9 / 10,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        skip(30 seconds);

        // price drops to $1000
        priceData = abi.encode(1000 ether);
        uint256 initialTotalPos = protocol.getTotalLongPositions();

        // liquidate the position
        protocol.liquidate(priceData, 1);
    }

    receive() external payable { }
}
