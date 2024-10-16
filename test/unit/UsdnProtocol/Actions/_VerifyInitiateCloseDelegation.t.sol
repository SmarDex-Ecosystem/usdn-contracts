// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { UsdnProtocolActionsUtilsLibrary } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolActionsUtilsLibrary.sol";
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
    bytes internal delegationData;

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
        delegationData = _getDelegationData(POSITION_OWNER_PK, domainSeparatorV4, delegation);
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by the owner with the correct values
     * @custom:given A signed delegation data by the position owner
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
            delegationData,
            domainSeparatorV4
        );
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by the owner with a compromised value
     * @custom:given A signed delegation data by the position owner
     * @custom:when The function _verifyInitiateCloseDelegation is called with a compromised value
     * @custom:then The transaction should revert with `UsdnProtocolInvalidDelegation`
     */
    function test_revertWhen_verifyInitiateCloseDelegationChangingParam() public {
        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidDelegation.selector);
        protocol.i_verifyInitiateCloseDelegation(
            delegation.posIdHash,
            delegation.amountToClose,
            delegation.userMinPrice,
            address(this), // the compromised value
            delegation.deadline,
            delegation.positionOwner,
            delegation.nonce,
            delegationData,
            domainSeparatorV4
        );
    }

    /**
     * @custom:scenario Verify a {initiateClosePosition} delegation signature by an attacker
     * @custom:given A signed delegation data by an attacker
     * @custom:when The function _verifyInitiateCloseDelegation is called with correct values
     * @custom:then The transaction should revert with `UsdnProtocolInvalidSignature`
     */
    function test_revertWhen_verifyInitiateCloseDelegationAttackerSignature() public {
        delegationData = _getDelegationData(ATTACKER_PK, domainSeparatorV4, delegation);

        vm.expectRevert(IUsdnProtocolErrors.UsdnProtocolInvalidSignature.selector);
        protocol.i_verifyInitiateCloseDelegation(
            delegation.posIdHash,
            delegation.amountToClose,
            delegation.userMinPrice,
            delegation.to,
            delegation.deadline,
            delegation.positionOwner,
            delegation.nonce,
            delegationData,
            domainSeparatorV4
        );
    }

    /**
     * @notice Get the signed delegation data
     * @param privateKey The signer private key
     * @param domainSeparator The domain separator v4
     * @param delegationToSign The delegation struct to sign
     * @return delegationData_ The delegation data
     */
    function _getDelegationData(
        uint256 privateKey,
        bytes32 domainSeparator,
        InitiateClosePositionDelegation memory delegationToSign
    ) internal pure returns (bytes memory delegationData_) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(
                    UsdnProtocolActionsUtilsLibrary.INITIATE_CLOSE_TYPEHASH,
                    delegationToSign.posIdHash,
                    delegationToSign.amountToClose,
                    delegationToSign.userMinPrice,
                    delegationToSign.to,
                    delegationToSign.deadline,
                    delegationToSign.positionOwner,
                    delegationToSign.positionCloser,
                    delegationToSign.nonce
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        delegationData_ = abi.encode(delegationToSign, abi.encodePacked(r, s, v));
    }
}
