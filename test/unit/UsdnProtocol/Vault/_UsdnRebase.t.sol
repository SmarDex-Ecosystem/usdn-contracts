// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";
import { RebaseHandler } from "test/unit/USDN/utils/RebaseHandler.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";

/**
 * @custom:feature The _usdnRebase internal function of the UsdnProtocolVault contract.
 * @custom:background Given a protocol instance that was initialized with more expo in the long side and rebase enabled
 * @custom:and A USDN rebase interval of 12 hours
 */
contract TestUsdnProtocolUsdnRebase is UsdnProtocolBaseFixture, IUsdnEvents {
    RebaseHandler rebaseHandler;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialLong = 10 ether;
        params.flags.enableUsdnRebase = true;
        super._setUp(params);

        rebaseHandler = new RebaseHandler();
        vm.prank(DEPLOYER);
        usdn.setRebaseHandler(rebaseHandler);

        vm.prank(ADMIN);
        protocol.setUsdnRebaseInterval(12 hours);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario USDN rebase
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is decreased by $100
     * @custom:and The `_usdnRebase` function is called
     * @custom:then The USDN token is rebased
     * @custom:and The callback handler is called
     * @custom:and The USDN price is lower than before
     */
    function test_rebase() public {
        uint256 usdnPrice = protocol.usdnPrice(params.initialPrice);
        assertEq(usdnPrice, 1 ether, "initial price");

        skip(1 hours);
        uint128 newPrice = params.initialPrice - 100 ether;
        protocol.updateBalances(newPrice);

        usdnPrice = protocol.usdnPrice(newPrice);
        assertGt(usdnPrice, 1 ether, "new USDN price compared to initial price");

        (bool rebased, bytes memory result) = protocol.i_usdnRebase(newPrice, true);
        assertTrue(rebased, "rebased");
        (uint256 oldDivisor, uint256 newDivisor) = abi.decode(result, (uint256, uint256));
        assertLt(newDivisor, oldDivisor, "callback worked");

        uint256 finalUsdnPrice = protocol.usdnPrice(newPrice);
        assertLt(finalUsdnPrice, usdnPrice, "final USDN price");
    }

    /**
     * @custom:scenario USDN rebase
     * @custom:given An initial USDN price of $1
     * @custom:and A callback handler that always fails
     * @custom:when The price of the asset is decreased by $100
     * @custom:and The `_usdnRebase` function is called
     * @custom:then The USDN token is not rebased
     * @custom:and The USDN price stays the same
     */
    function test_rebaseCallbackFails() public {
        rebaseHandler.setShouldFail(true);

        uint256 usdnPrice = protocol.usdnPrice(params.initialPrice);
        assertEq(usdnPrice, 1 ether, "initial price");

        skip(1 hours);
        uint128 newPrice = params.initialPrice - 100 ether;
        protocol.updateBalances(newPrice);

        usdnPrice = protocol.usdnPrice(newPrice);
        assertGt(usdnPrice, 1 ether, "new USDN price compared to initial price");

        (bool rebased, bytes memory result) = protocol.i_usdnRebase(newPrice, true);
        assertFalse(rebased, "rebased");
        assertEq(result, "", "callback result");

        uint256 finalUsdnPrice = protocol.usdnPrice(newPrice);
        assertEq(finalUsdnPrice, usdnPrice, "final USDN price");
    }

    /**
     * @custom:scenario USDN rebase before the interval has passed
     * @custom:given An initial USDN price of $1 and a recent rebase check
     * @custom:when The price of the asset is decreased by $100 but we wait less than the rebase interval
     * @custom:then The USDN token is not rebased
     */
    function test_rebaseCheckInterval() public {
        skip(1 hours);

        // initialize _lastRebaseCheck
        protocol.i_usdnRebase(params.initialPrice, true);
        assertGt(protocol.getLastRebaseCheck(), 0, "last rebase check");
        uint256 usdnPrice = protocol.usdnPrice(params.initialPrice);
        assertEq(usdnPrice, 1 ether, "initial price");

        // this new price would normally trigger a rebase
        uint128 newPrice = params.initialPrice - 100 ether;

        skip(protocol.getUsdnRebaseInterval() - 1);
        protocol.updateBalances(newPrice);

        usdnPrice = protocol.usdnPrice(newPrice);
        assertGt(usdnPrice, 1 ether, "new USDN price compared to initial price");
        // since we checked more recently than `_usdnRebaseInterval`, we do not rebase
        (bool rebased,) = protocol.i_usdnRebase(newPrice, false);
        assertFalse(rebased, "no rebase");
    }

    /**
     * @custom:scenario USDN rebase when the divisor is already MIN_DIVISOR
     * @custom:given A USDN token already set to have its divisor to MIN_DIVISOR
     * @custom:when The rebase function is called
     * @custom:then The USDN token is not rebased
     */
    function test_rebaseCheckMinDivisor() public {
        vm.startPrank(DEPLOYER);
        usdn.grantRole(usdn.REBASER_ROLE(), address(this));
        vm.stopPrank();
        usdn.rebase(usdn.MIN_DIVISOR());

        (bool rebased,) = protocol.i_usdnRebase(params.initialPrice, true);
        assertFalse(rebased, "no rebase");
    }

    /**
     * @custom:scenario USDN rebase when the price is lower than the threshold
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $15
     * @custom:and The price of USDN increases but is still lower than the rebase threshold
     * @custom:then The USDN token is not rebased
     */
    function test_rebasePriceLowerThanThreshold() public {
        // initialize _lastRebaseCheck
        protocol.i_usdnRebase(params.initialPrice, true);
        assertGt(protocol.getLastRebaseCheck(), 0, "last rebase check");
        uint256 usdnPrice = protocol.usdnPrice(params.initialPrice);
        assertEq(usdnPrice, 1 ether, "initial price");

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        assertGt(block.timestamp, protocol.getLastRebaseCheck() + protocol.getUsdnRebaseInterval(), "time elapsed");

        uint128 newPrice = params.initialPrice - 15 ether;
        protocol.updateBalances(newPrice);
        usdnPrice = protocol.usdnPrice(newPrice);
        assertGt(usdnPrice, 1 ether, "new USDN price compared to initial price");
        assertLt(usdnPrice, protocol.getUsdnRebaseThreshold(), "new USDN price compared to threshold");

        // since the price of USDN didn't reach the threshold, we do not rebase
        (bool rebased,) = protocol.i_usdnRebase(newPrice, true);
        assertFalse(rebased, "no rebase");
    }
}
