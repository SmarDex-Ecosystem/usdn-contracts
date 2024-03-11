// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER } from "test/utils/Constants.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";
import { Position, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature Test the rebasing of the USDN token depending on its price
 * @custom:background Given a protocol instance that was initialized with more expo in the long side and rebase enabled
 */
contract TestUsdnProtocolRebase is UsdnProtocolBaseFixture, IUsdnEvents {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 5 ether;
        params.initialLong = 10 ether;
        params.enablePositionFees = false;
        params.enableProtocolFees = false;
        params.enableFunding = false;
        params.enableUsdnRebase = true;
        super._setUp(params);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        usdn.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Rebasing of the USDN token depending on the asset price
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $100 and we call `liquidate`
     * @custom:then The USDN token is rebased
     * @custom:and The USDN divisor and total supply are adjusted as expected
     */
    function test_usdnRebaseWhenLiquidate() public {
        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        skip(1 hours);

        uint128 newPrice = params.initialPrice - 100 ether;

        // price goes above rebase threshold due to change in asset price
        uint256 usdnPrice = protocol.usdnPrice(newPrice);
        assertGt(usdnPrice, protocol.getUsdnRebaseThreshold(), "price before rebase");

        // calculate expected new USDN divisor
        uint256 expectedVaultBalance =
            uint256(protocol.vaultAssetAvailableWithFunding(newPrice, uint128(block.timestamp - 30)));
        uint256 expectedTotalSupply = protocol.i_calcRebaseTotalSupply(
            expectedVaultBalance,
            newPrice,
            protocol.getTargetUsdnPrice(),
            protocol.getUsdnDecimals(),
            protocol.getAssetDecimals()
        );
        uint256 expectedDivisor = usdn.totalSupply() * usdn.divisor() / expectedTotalSupply;

        // we do not need to wait for the rebase interval to pass because `liquidate` overrides the check

        // rebase (no liquidation happens)
        vm.expectEmit();
        emit Rebase(usdn.MAX_DIVISOR(), expectedDivisor);
        protocol.liquidate(abi.encode(newPrice), 0);

        assertApproxEqAbs(
            protocol.usdnPrice(newPrice, uint128(block.timestamp - 30)),
            protocol.getTargetUsdnPrice(),
            1,
            "price after rebase"
        );
        assertApproxEqRel(usdn.totalSupply(), expectedTotalSupply, 1, "total supply");
        assertEq(protocol.getBalanceVault(), expectedVaultBalance, "vault balance");
    }

    /**
     * @custom:scenario USDN rebase before the interval has passed
     * @custom:given An initial USDN price of $1 and a recent rebase check
     * @custom:when The price of the asset is reduced by $100 but we wait less than the rebase interval
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

        // update balances
        protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));
        // since we checked more recently than `_usdnRebaseInterval`, we do not rebase
        vm.recordLogs();
        protocol.i_usdnRebase(newPrice, false);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            // no log is a rebase log
            assertTrue(logs[i].topics[0] != Rebase.selector, "log topic");
        }
    }

    /**
     * @custom:scenario USDN rebase when the price is lower than the threshold
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $10
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

        uint128 newPrice = params.initialPrice - 10 ether;
        usdnPrice = protocol.usdnPrice(newPrice);
        assertGt(usdnPrice, 1 ether, "new USDN price compared to initial price");
        assertLt(usdnPrice, protocol.getUsdnRebaseThreshold(), "new USDN price compared to threshold");

        // update balances
        protocol.i_applyPnlAndFunding(newPrice, uint128(block.timestamp));

        // since the price of USDN didn't reach the threshold, we do not rebase
        vm.recordLogs();
        protocol.i_usdnRebase(newPrice, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            // no log is a rebase log
            assertTrue(logs[i].topics[0] != Rebase.selector, "log topic");
        }
    }

    /**
     * @custom:scenario Rebasing of the USDN token when initiating a deposit
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $100 and we call `initiateDeposit`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenInitiateDeposit() public {
        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        uint128 newPrice = params.initialPrice - 100 ether;
        assertEq(protocol.getLastRebaseCheck(), 0, "rebase never checked");

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.initiateDeposit(1 ether, abi.encode(newPrice), "");
    }

    /**
     * @custom:scenario Rebasing of the USDN token when validating a deposit
     * @custom:given An initial USDN price of $1 and a deposit which was initiated
     * @custom:when The price of the asset is reduced by $100 and we call `validateDeposit`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenValidateDeposit() public {
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 1 ether, params.initialPrice);

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        uint128 newPrice = params.initialPrice - 100 ether;

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.validateDeposit(abi.encode(newPrice), "");
    }

    /**
     * @custom:scenario Rebasing of the USDN token when initiating a withdrawal
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $100 and we call `initiateWithdrawal`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenInitiateWithdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, params.initialPrice);

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.initiateWithdrawal(100 ether, abi.encode(newPrice), "");
    }

    /**
     * @custom:scenario Rebasing of the USDN token when validating a withdrawal
     * @custom:given An initial USDN price of $1 and a withdrawal which was initiated
     * @custom:when The price of the asset is reduced by $100 and we call `validateWithdrawal`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenValidateWithdrawal() public {
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateWithdrawal, 1 ether, params.initialPrice);

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.validateWithdrawal(abi.encode(newPrice), "");
    }

    /**
     * @custom:scenario Rebasing of the USDN token when initiating a long
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $100 and we call `initiateOpenPosition`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenInitiateOpenPosition() public {
        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        uint128 newPrice = params.initialPrice - 100 ether;
        assertEq(protocol.getLastRebaseCheck(), 0, "rebase never checked");

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.initiateOpenPosition(1 ether, params.initialPrice / 2, abi.encode(newPrice), "");
    }

    /**
     * @custom:scenario Rebasing of the USDN token when validating a new long
     * @custom:given An initial USDN price of $1 and a long which was initiated
     * @custom:when The price of the asset is reduced by $100 and we call `validateOpenPosition`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenValidateOpenPosition() public {
        setUpUserPositionInLong(
            address(this), ProtocolAction.InitiateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.validateOpenPosition(abi.encode(newPrice), "");
    }

    /**
     * @custom:scenario Rebasing of the USDN token when initiating a long closing
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $100 and we call `initiateClosePosition`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenInitiateClosePosition() public {
        (int24 tick, uint256 tickVersion, uint256 index) = setUpUserPositionInLong(
            address(this), ProtocolAction.ValidateOpenPosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.initiateClosePosition(tick, tickVersion, index, abi.encode(newPrice), "");
    }

    /**
     * @custom:scenario Rebasing of the USDN token when validating a position closing
     * @custom:given An initial USDN price of $1 and a close position which was initiated
     * @custom:when The price of the asset is reduced by $100 and we call `validateClosePosition`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenValidateClosePosition() public {
        setUpUserPositionInLong(
            address(this), ProtocolAction.InitiateClosePosition, 1 ether, params.initialPrice / 2, params.initialPrice
        );

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.validateClosePosition(abi.encode(newPrice), "");
    }
}
