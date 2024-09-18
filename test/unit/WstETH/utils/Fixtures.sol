// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IStETH } from "../../../../src/interfaces/IStEth.sol";
import { MockStETH } from "../../../../src/utils/MockStETH.sol";
import { MockWstETH } from "../../../../src/utils/MockWstETH.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";

/**
 * @title WstEthFixture
 * @dev Utils for testing MockStETh.sol
 */
contract WstEthFixture is BaseFixture {
    MockStETH public stETH;
    MockWstETH public wstETH;

    function setUp() public virtual {
        stETH = new MockStETH();
        wstETH = new MockWstETH(IStETH(address(stETH)));
    }
}
