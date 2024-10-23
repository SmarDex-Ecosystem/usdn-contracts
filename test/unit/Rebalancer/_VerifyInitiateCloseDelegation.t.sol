// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { RebalancerFixture } from "./utils/Fixtures.sol";

/**
 * @custom:feature The {_verifyInitiateCloseDelegation} function of the rebalancer contract
 * @custom:background Given a rebalancer contract with a 1 ether balance
 */
contract TestRebalancerVerifyInitiateCloseDelegation is RebalancerFixture {
    uint256 internal constant PK = 1;
    uint256 internal constant ATTACKER_PK = 2;
    address internal user = vm.addr(PK);
    uint256 internal initialNonce;

    function setUp() public {
        super._setUp();
        initialNonce = rebalancer.getNonce(user);

        delegation = InitiateClosePositionDelegation({
            amount: 10 ether,
            to: user,
            userMinPrice: 4000 ether,
            deadline: type(uint256).max,
            depositOwner: user,
            depositCloser: address(this),
            nonce: initialNonce
        });
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by the owner with the correct values
     * @custom:given A signed delegation by the deposit owner
     * @custom:and A valid deposit owner
     * @custom:when The function {_verifyInitiateCloseDelegation} is called with correct values
     * @custom:then The transaction should not revert
     */
    function test_verifyInitiateCloseDelegation() public {
        bytes memory signature = _getDelegationSignature(PK, delegation);
        bytes memory delegationData = abi.encode(user, signature);

        address depositOwner = rebalancer.i_verifyInitiateCloseDelegation(
            delegation.amount, delegation.to, delegation.userMinPrice, delegation.deadline, delegationData
        );

        assertEq(depositOwner, user, "The depositOwner should be the user");
        assertEq(rebalancer.getNonce(user), initialNonce + 1, "The depositOwner nonce should be incremented");
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by the owner with a compromised value
     * @custom:given A valid signed delegation by the deposit owner
     * @custom:and A valid deposit owner
     * @custom:when The function {_verifyInitiateCloseDelegation} is called with a compromised value
     * @custom:then The transaction should revert with {RebalancerInvalidDelegationSignature}
     */
    function test_RevertWhen_verifyInitiateCloseDelegationChangeParam() public {
        bytes memory signature = _getDelegationSignature(PK, delegation);
        bytes memory delegationData = abi.encode(user, signature);

        vm.expectRevert(RebalancerInvalidDelegationSignature.selector);
        rebalancer.i_verifyInitiateCloseDelegation(
            delegation.amount, address(this), delegation.userMinPrice, delegation.deadline, delegationData
        );
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by the owner with a compromised value
     * @custom:given A signed delegation by the deposit owner
     * @custom:and An invalid deposit owner
     * @custom:when The function {_verifyInitiateCloseDelegation} is called with a compromised deposit owner
     * @custom:then The transaction should revert with {RebalancerInvalidDelegationSignature}
     */
    function test_RevertWhen_verifyInitiateCloseDelegationInvalidOwner() public {
        bytes memory signature = _getDelegationSignature(PK, delegation);
        bytes memory delegationData = abi.encode(address(this), signature);

        vm.expectRevert(RebalancerInvalidDelegationSignature.selector);
        rebalancer.i_verifyInitiateCloseDelegation(
            delegation.amount, delegation.to, delegation.userMinPrice, delegation.deadline, delegationData
        );
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by an attacker
     * @custom:given A signed delegation by an attacker
     * @custom:when The function {_verifyInitiateCloseDelegation} is called with correct values
     * @custom:then The transaction should revert with {RebalancerInvalidDelegationSignature}
     */
    function test_RevertWhen_verifyInitiateCloseDelegationAttackerSignature() public {
        bytes memory signature = _getDelegationSignature(ATTACKER_PK, delegation);
        bytes memory delegationData = abi.encode(user, signature);

        vm.expectRevert(RebalancerInvalidDelegationSignature.selector);
        rebalancer.i_verifyInitiateCloseDelegation(
            delegation.amount, delegation.to, delegation.userMinPrice, delegation.deadline, delegationData
        );
    }
}
