// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";
import { TransferCallback } from "../utils/TransferCallback.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

/**
 * @custom:feature The initiateWithdrawal function of the USDN Protocol
 * @custom:background Given a protocol initialized at equilibrium.
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolActionsInitiateWithdrawalWithCallback is TransferCallback, UsdnProtocolBaseFixture {
    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;
    uint128 internal constant USDN_AMOUNT = 1000 ether;
    uint152 internal withdrawShares;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        transferActive = true;
        withdrawShares = USDN_AMOUNT * uint152(usdn.MAX_DIVISOR());
        usdn.approve(address(protocol), type(uint256).max);
        // user deposits wstETH at price $2000
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, DEPOSIT_AMOUNT, 2000 ether);
    }

    /**
     * @custom:scenario Initiate a withdrawal by using callback for USDN shares transfer
     * @custom:when The user initiates a deposit of `withdrawShares` with a contract that has callback to transfer
     * USDN shares
     * @custom:then The protocol receives `withdrawShares` USDN shares
     */
    function test_initiateWithdrawalWithCallback() public {
        uint256 balanceBefore = usdn.sharesOf(address(protocol));
        bool success = protocol.initiateWithdrawal{ value: protocol.getSecurityDepositValue() }(
            withdrawShares,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(2000 ether),
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success);
        assertEq(usdn.sharesOf(address(protocol)), balanceBefore + withdrawShares);
    }

    /**
     * @custom:scenario Initiate a withdrawal by using callback without insufficient transfer of USDN shares
     * @custom:when The user initiates a withdrawal of `withdrawShares` with a contract that does not transfer shares
     * @custom:then the protocol revert with `UsdnProtocolPaymentCallbackFailed` error
     */
    function test_RevertWhen_initiateWithdrawalCallbackNoTransfer() public {
        transferActive = false;
        uint256 securityDeposit = protocol.getSecurityDepositValue();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.initiateWithdrawal{ value: securityDeposit }(
            withdrawShares,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(2000 ether),
            EMPTY_PREVIOUS_DATA
        );
    }
}
