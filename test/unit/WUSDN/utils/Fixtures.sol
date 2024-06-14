// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { WusdnHandler } from "./Handler.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { IWusdnErrors } from "../../../../src/interfaces/Usdn/IWusdnErrors.sol";
import { IWusdnEvents } from "../../../../src/interfaces/Usdn/IWusdnEvents.sol";
import { Wusdn } from "../../../../src/Usdn/Wusdn.sol";
import { Usdn } from "../../../../src/Usdn/Usdn.sol";

/**
 * @title WusdnTokenFixture
 * @dev Utils for testing WUSDN token
 */
contract WusdnTokenFixture is BaseFixture, IWusdnErrors, IWusdnEvents {
    /// @notice WUSDN token handler
    WusdnHandler public wusdn;
    /// @notice USDN token decimals
    uint256 public usdnDecimals;
    /// @notice USDN token
    Usdn public usdn;

    function setUp() public virtual {
        usdn = new Usdn(address(0), address(0));

        wusdn = new WusdnHandler(usdn);
        usdnDecimals = usdn.decimals();

        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.MINTER_ROLE(), address(wusdn));
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        usdn.mint(address(this), 100 ether);
    }

    // force ignore from coverage report
    // until https://github.com/foundry-rs/foundry/issues/2988 is fixed
    function test() public virtual override { }
}
