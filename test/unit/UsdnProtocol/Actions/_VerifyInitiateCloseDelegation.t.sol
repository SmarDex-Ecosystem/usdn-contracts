// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature Test the _verifyInitiateCloseDelegation internal function
 * @custom:given A initiated protocol
 */
contract TestUsdnProtocolVerifyInitiateCloseDelegation is UsdnProtocolBaseFixture {
    uint256 internal constant POSITION_OWNER_PK = 1;
    uint256 internal constant ATTACKER_PK = 2;
    address internal positionOwner = vm.addr(POSITION_OWNER_PK);

    InitiateClosePositionDelegation internal delegation;
    bytes32 internal domainSeparatorV4;
    bytes internal delegationSignature;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);
        delegation = InitiateClosePositionDelegation(
            keccak256(abi.encode(PositionId(10_589, 1, 45))),
            100 ether,
            4000 ether,
            USER_1,
            type(uint256).max,
            positionOwner,
            address(this),
            121
        );

        domainSeparatorV4 = protocol.i_domainSeparatorV4();
        delegationSignature = _getDelegationSignature(POSITION_OWNER_PK, domainSeparatorV4, delegation);
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by the owner with the correct values
     * @custom:given A signed delegation by the position owner
     * @custom:when The function _verifyInitiateCloseDelegation is called with correct values
     * @custom:then The transaction should not revert
     */
    function test_verifyInitiateCloseDelegation() public view {
        protocol.i_verifyInitiateCloseDelegation(
            delegation.posIdHash,
            delegation.amountToClose,
            delegation.userMinPrice,
            delegation.to,
            delegation.deadline,
            delegation.positionOwner,
            delegation.nonce,
            delegationSignature,
            domainSeparatorV4
        );
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by the owner with a compromised value
     * @custom:given A signed delegation by the position owner
     * @custom:when The function _verifyInitiateCloseDelegation is called with a compromised value
     * @custom:then The transaction should revert with `UsdnProtocolInvalidDelegation`
     */
    function test_revertWhen_verifyInitiateCloseDelegationChangeParam() public {
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidDelegation.selector);
        protocol.i_verifyInitiateCloseDelegation(
            delegation.posIdHash,
            delegation.amountToClose,
            delegation.userMinPrice,
            address(this), // the compromised value
            delegation.deadline,
            delegation.positionOwner,
            delegation.nonce,
            delegationSignature,
            domainSeparatorV4
        );
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by an attacker
     * @custom:given A signed delegation by an attacker
     * @custom:when The function _verifyInitiateCloseDelegation is called with correct values
     * @custom:then The transaction should revert with `UsdnProtocolInvalidDelegation`
     */
    function test_revertWhen_verifyInitiateCloseDelegationAttackerSignature() public {
        delegationSignature = _getDelegationSignature(ATTACKER_PK, domainSeparatorV4, delegation);

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidDelegation.selector);
        protocol.i_verifyInitiateCloseDelegation(
            delegation.posIdHash,
            delegation.amountToClose,
            delegation.userMinPrice,
            delegation.to,
            delegation.deadline,
            delegation.positionOwner,
            delegation.nonce,
            delegationSignature,
            domainSeparatorV4
        );
    }
}
