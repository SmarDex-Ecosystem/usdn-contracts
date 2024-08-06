// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature Test the functions in the vault contract
 * @custom:background Given a protocol instance that was initialized with default params
 */
contract TestUsdnProtocolVault is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
    }

    /**
     * @custom:scenario Check the splitting of the withdrawal shares amount into two parts
     * @custom:given An amount to be split in the range of uint152
     * @custom:when The amount is split with the protocol function and then merged back
     * @custom:then The original amount should be the same as the input
     * @param amount The amount to be split and merged
     */
    function testFuzz_withdrawalAmountSplitting(uint152 amount) public view {
        uint24 lsb = protocol.i_calcWithdrawalAmountLSB(amount);
        uint128 msb = protocol.i_calcWithdrawalAmountMSB(amount);
        uint256 res = protocol.i_mergeWithdrawalAmountParts(lsb, msb);
        assertEq(res, amount, "Amount splitting and merging failed");
    }
}
