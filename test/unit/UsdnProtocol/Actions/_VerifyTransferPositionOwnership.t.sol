// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";

/**
 * @custom:feature Test the {_verifyTransferPositionOwnershipDelegation} internal function
 * @custom:given A initiated protocol
 */
contract TestUsdnProtocolVerifyTransferPositionOwnershipDelegation is UsdnProtocolBaseFixture {
    uint256 internal constant POSITION_OWNER_PK = 1;
    uint256 internal constant ATTACKER_PK = 2;
    address internal _positionOwner = vm.addr(POSITION_OWNER_PK);

    bytes32 internal _domainSeparatorV4;
    bytes internal _delegationSignature;
    uint256 internal _initialNonce;
    PositionId internal _posId = PositionId(10_589, 1, 45);
    TransferPositionOwnershipDelegation internal _delegation;

    function setUp() public {
        _setUp(DEFAULT_PARAMS);
        _initialNonce = protocol.getNonce(_positionOwner);

        _delegation = TransferPositionOwnershipDelegation(
            keccak256(abi.encode(_posId)), _positionOwner, USER_1, address(this), _initialNonce
        );

        _domainSeparatorV4 = protocol.domainSeparatorV4();
        _delegationSignature =
            _getTransferPositionDelegationSignature(POSITION_OWNER_PK, _domainSeparatorV4, _delegation);
    }

    /**
     * @custom:scenario Verify a {transferPositionOwnership} delegation signature by the owner with the correct values
     * @custom:given A signed delegation by the position owner
     * @custom:when The function {_verifyTransferPositionOwnershipDelegation} is called with correct values
     * @custom:then The transaction should not revert
     */
    function test_verifyTransferPositionOwnershipDelegation() public {
        protocol.i_verifyTransferPositionOwnershipDelegation(
            _posId, _delegationSignature, _domainSeparatorV4, _positionOwner, USER_1
        );

        assertEq(protocol.getNonce(_positionOwner), _initialNonce + 1, "position owner nonce should be incremented");
    }

    /**
     * @custom:scenario Verify a {transferPositionOwnership} delegation signature by the owner with a compromised value
     * @custom:given A signed delegation by the position owner
     * @custom:when The function {_verifyTransferPositionOwnershipDelegation} is called with a compromised value
     * @custom:then The transaction should revert with {UsdnProtocolInvalidDelegationSignature}
     */
    function test_verifyTransferPositionOwnershipDelegationChangeParam() public {
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidDelegationSignature.selector);
        protocol.i_verifyTransferPositionOwnershipDelegation(
            _posId, _delegationSignature, _domainSeparatorV4, _positionOwner, address(this)
        );
    }

    /**
     * @custom:scenario Verify a {transferPositionOwnership} delegation signature by an attacker
     * @custom:given A signed delegation by an attacker
     * @custom:when The function {_verifyTransferPositionOwnershipDelegation} is called with correct values
     * @custom:then The transaction should revert with {UsdnProtocolInvalidDelegationSignature}
     */
    function test_verifyTransferPositionOwnershipDelegationAttackerSignature() public {
        _delegationSignature = _getTransferPositionDelegationSignature(ATTACKER_PK, _domainSeparatorV4, _delegation);

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidDelegationSignature.selector);
        protocol.i_verifyTransferPositionOwnershipDelegation(
            _posId, _delegationSignature, _domainSeparatorV4, _positionOwner, USER_1
        );
    }
}
