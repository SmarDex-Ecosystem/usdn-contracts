// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IUsdnProtocol } from "../../../../../src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

import { DEPLOYER } from "../../../../utils/Constants.sol";
import { BaseFixture } from "../../../../utils/Fixtures.sol";
import { FeeManager } from "../verifierContracts/llo-feeds/FeeManager.sol";
import { RewardManager } from "../verifierContracts/llo-feeds/RewardManager.sol";
import { Verifier } from "../verifierContracts/llo-feeds/Verifier.sol";
import { VerifierProxy } from "../verifierContracts/llo-feeds/VerifierProxy.sol";
import { SimpleWriteAccessController } from "../verifierContracts/shared/access/SimpleWriteAccessController.sol";

contract ChainlinkDataStreamFixture is BaseFixture {
    address internal constant USDN_PROTOCOL_ADDRESS = 0x656cB8C6d154Aad29d8771384089be5B5141f01a;
    address internal constant MAINNET_LINK_ADDRESS = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address internal constant NATIVE_ADDRESS = 0x4200000000000000000000000000000000000006;

    IUsdnProtocol internal _protocol;
    SimpleWriteAccessController internal _controller;
    VerifierProxy internal _verifierProxy;
    Verifier internal _verifier;
    RewardManager internal _rewardManager;
    FeeManager internal _feeManager;

    function _setUp() internal {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        _protocol = IUsdnProtocol(USDN_PROTOCOL_ADDRESS);

        vm.startPrank(DEPLOYER);
        _controller = new SimpleWriteAccessController();
        _verifierProxy = new VerifierProxy(_controller);
        _rewardManager = new RewardManager(MAINNET_LINK_ADDRESS);
        _feeManager =
            new FeeManager(MAINNET_LINK_ADDRESS, NATIVE_ADDRESS, address(_verifierProxy), address(_rewardManager));
        _rewardManager.setFeeManager(address(_feeManager));
        _verifier = new Verifier(address(_verifierProxy));

        _verifierProxy.setFeeManager(_feeManager);

        _verifierProxy.initializeVerifier(address(_verifier));
        vm.stopPrank();
    }

    function _decodeBytes(bytes memory transactions) internal pure returns (bytes[] memory results_) {
        uint256 txCount;

        results_ = new bytes[](100_000);
        uint256 i = 0x20;
        uint256 offset = 0x35;
        uint256 length = transactions.length;
        uint256 dataLength;

        while (i < length) {
            uint256 currentOffset = i + offset;
            dataLength = length - currentOffset;
            results_[txCount] = _slice(transactions, currentOffset, dataLength);
            i += 0x55 + dataLength;
            txCount += 1;
        }

        assembly {
            mstore(results_, txCount)
        }
    }

    function _slice(bytes memory _bytes, uint256 _start, uint256 _length) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        // Check length is 0. `iszero` return 1 for `true` and 0 for `false`.
        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // Calculate length mod 32 to handle slices that are not a multiple of 32 in size.
                let lengthmod := and(_length, 31)

                // tempBytes will have the following format in memory: <length><data>
                // When copying data we will offset the start forward to avoid allocating additional memory
                // Therefore part of the length area will be written, but this will be overwritten later anyways.
                // In case no offset is require, the start is set to the data region (0x20 from the tempBytes)
                // mc will be used to keep track where to copy the data to.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // Same logic as for mc is applied and additionally the start offset specified for the method is
                    // added
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    // increase `mc` and `cc` to read the next word from memory
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // Copy the data from source (cc location) to the slice data (mc location)
                    mstore(mc, mload(cc))
                }

                // Store the length of the slice. This will overwrite any partial data that
                // was copied when having slices that are not a multiple of 32.
                mstore(tempBytes, _length)

                // update free-memory pointer
                // allocating the array padded to 32 bytes like the compiler does now
                // To set the used memory as a multiple of 32, add 31 to the actual memory usage (mc)
                // and remove the modulo 32 (the `and` with `not(31)`)
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            // if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                // zero out the 32 bytes slice we are about to return
                // we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                // update free-memory pointer
                // tempBytes uses 32 bytes in memory (even when empty) for the length.
                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }
}
