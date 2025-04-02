// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console } from "forge-std/Test.sol";

import { Usdn } from "../../../../../src/Usdn/Usdn.sol";

/**
 * @notice A USDN token handler for invariant testing of the USDN protocol
 * @dev This handler is very simple and just serves to test some out-of-band transfers and burns while using the
 * protocol
 */
contract UsdnHandler is Usdn, Test {
    constructor() Usdn(address(0), address(0)) { }

    function burnSharesTest(uint256 value) external {
        if (sharesOf(msg.sender) == 0) {
            return;
        }
        value = _bound(value, 1, sharesOf(msg.sender));
        _burnShares(msg.sender, value, _convertToTokens(value, Rounding.Closest, _divisor));
        console.log("USDN burn %s shares from %s", value, msg.sender);
    }

    function transferSharesTest(address to, uint256 value) external {
        if (sharesOf(msg.sender) == 0 || to == address(0)) {
            return;
        }
        value = _bound(value, 1, sharesOf(msg.sender));
        _transferShares(msg.sender, to, value, _convertToTokens(value, Rounding.Closest, _divisor));
        console.log("USDN transfer %s shares from %s to %s ", value, msg.sender, to);
    }
}
