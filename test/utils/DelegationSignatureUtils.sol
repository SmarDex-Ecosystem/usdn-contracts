// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";

import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

contract DelegationSignatureUtils is Test {
    struct InitiateClosePositionDelegation {
        bytes32 posIdHash;
        uint128 amountToClose;
        uint256 userMinPrice;
        address to;
        uint256 deadline;
        address positionOwner;
        address positionCloser;
        uint256 nonce;
    }

    struct TransferPositionOwnershipDelegation {
        bytes32 posIdHash;
        address positionOwner;
        address newPositionOwner;
        address delegatedAddress;
        uint256 nonce;
    }

    /**
     * @notice Get the signed delegation data
     * @param privateKey The signer private key
     * @param domainSeparator The domain separator v4
     * @param delegationToSign The delegation struct to sign
     * @return delegationSignature_ The initiateClosePosition eip712 delegation signature
     */
    function _getDelegationSignature(
        uint256 privateKey,
        bytes32 domainSeparator,
        InitiateClosePositionDelegation memory delegationToSign
    ) internal pure returns (bytes memory delegationSignature_) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(
                    Constants.INITIATE_CLOSE_TYPEHASH,
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

        delegationSignature_ = abi.encodePacked(r, s, v);
    }

    /**
     * @notice Get the signed delegation signature for {transferPositionOwnership}
     * @param privateKey The signer private key
     * @param domainSeparator The domain separator v4
     * @param delegationToSign The delegation struct to sign
     * @return delegationSignature_ The initiateClosePosition eip712 delegation signature
     */
    function _getTransferPositionDelegationSignature(
        uint256 privateKey,
        bytes32 domainSeparator,
        TransferPositionOwnershipDelegation memory delegationToSign
    ) internal pure returns (bytes memory delegationSignature_) {
        bytes32 digest = MessageHashUtils.toTypedDataHash(
            domainSeparator,
            keccak256(
                abi.encode(
                    Constants.TRANSFER_POSITION_OWNERSHIP_TYPEHASH,
                    delegationToSign.posIdHash,
                    delegationToSign.positionOwner,
                    delegationToSign.newPositionOwner,
                    delegationToSign.delegatedAddress,
                    delegationToSign.nonce
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        delegationSignature_ = abi.encodePacked(r, s, v);
    }
}
