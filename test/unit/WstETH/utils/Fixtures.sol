// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { BaseFixture } from "../../../utils/Fixtures.sol";

import { StETH } from "../../../../src/utils/sepolia/tokens/StETH.sol";
import { WstETH } from "../../../../src/utils/sepolia/tokens/WstETH.sol";

/**
 * @title WstEthFixture
 * @dev Utils for testing StETh.sol
 */
contract WstEthFixture is BaseFixture {
    StETH public stETH;
    WstETH public wstETH;

    function setUp() public virtual {
        stETH = new StETH();
        wstETH = new WstETH(stETH);
    }
}
