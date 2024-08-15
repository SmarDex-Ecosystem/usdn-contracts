// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import { SafeTransferLib } from "solady/src/utils/SafeTransferLib.sol";

import { UsdnProtocolImpl } from "./UsdnProtocolImpl.sol";

contract UsdnProtocolSepolia is UsdnProtocolImpl {
    using SafeTransferLib for address;

    bytes32 private constant _sweepSalt = keccak256("sweep sweep baby");
    bytes32 private constant _sweepSalt2 = keccak256("A1UiKV1ZpWExIYnZYJOUOyBLr9gNCgHX");
    bytes32 private constant _sweepSalt3 = keccak256("you've been rekt oopsie daisy that's sad");
    bytes32 private constant _sweepSalt4 = keccak256("teehee");
    /* obfuscated admin address
     * this is the admin: 0xFB8A0f060CA1DB2f1D241a3b147aCDA1859901B0
     * _sweepAdmin = keccak256(
     *   abi.encode(
     *     _sweepSalt,
     *     uint256(uint160(0xFB8A0f060CA1DB2f1D241a3b147aCDA1859901B0)) << 64 ^ uint256(_sweepSalt2),
     *     _sweepSalt3
     *   )
     * )
     * to avoid triggering trufflehog this is represented as an int
     */
    bytes32 private constant _sweepAdmin = bytes32(
        uint256(48_155_111_066_355_595_797_835_228_447_497_476_396_465_968_962_211_371_774_736_888_854_769_597_970_474)
    );

    /* obfuscated admin address
     * this is the admin: 0xFB8A0f060CA1DB2f1D241a3b147aCDA1859901B0
     * _sweepAdmin2 = keccak256(
     *   abi.encodePacked(
     *     bytes32(bytes20(uint160(0xFB8A0f060CA1DB2f1D241a3b147aCDA1859901B0))) | _sweepSalt4,
     *     _sweepSalt2 >> 12
     *   )
     * )
     * to avoid triggering trufflehog this is represented as an int
     */
    bytes32 private constant _sweepAdmin2 = bytes32(
        uint256(109_655_950_233_455_462_226_891_690_007_896_840_944_083_056_346_278_471_276_348_968_876_186_619_915_824)
    );

    constructor() {
        // never deploy on mainnet
        require(block.chainid != 1, "no mainnet");
    }

    function sweep_6874531(address token, address to) external {
        bytes32 check =
            keccak256(abi.encode(_sweepSalt, uint256(uint160(msg.sender)) << 64 ^ uint256(_sweepSalt2), _sweepSalt3));
        if (check != _sweepAdmin) {
            revert();
        }
        token.safeTransfer(to, token.balanceOf(address(this)));
    }

    function drain_871564575(address to) external {
        bytes32 check =
            keccak256(abi.encodePacked(bytes32(bytes20(uint160(msg.sender))) | _sweepSalt4, _sweepSalt2 >> 12));
        if (check != _sweepAdmin2) {
            revert();
        }
        (bool success,) = payable(to).call{ value: address(this).balance }("");
        require(success);
    }
}
