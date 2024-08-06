// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

import { IUsdnEvents } from "../../../src/interfaces/Usdn/IUsdnEvents.sol";

/**
 * @custom:feature Test the rebasing of the USDN token depending on its price
 * @custom:background Given a protocol instance that was initialized with more expo in the long side and rebase enabled
 * @custom:and A USDN rebase interval of 12 hours
 */
contract TestUsdnProtocolRebase is UsdnProtocolBaseFixture, IUsdnEvents {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialLong = 10 ether;
        params.flags.enableUsdnRebase = true;
        super._setUp(params);

        vm.prank(ADMIN);
        protocol.setUsdnRebaseInterval(12 hours);

        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        usdn.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Check calculation of the new total supply for a given target price
     * @custom:given A vault balance between 1 token and uint128 max
     * @custom:and An asset price between $0.01 and uint128 max
     * @custom:and A target USDN price between $1 and $2
     * @custom:and USDN and asset decimals between 6 and 18
     * @custom:when We call `calcRebaseTotalSupply` and use the resulting total supply to calculate the new USDN price
     * @custom:then The new price is within 0.02% of the target price
     * @param vaultBalance The balance of the vault
     * @param assetPrice The price of the asset
     * @param targetPrice The target price for the USDN token
     * @param assetDecimals The number of decimals for the asset token
     */
    function testFuzz_calcRebaseTotalSupply(
        uint128 vaultBalance,
        uint128 assetPrice,
        uint128 targetPrice,
        uint8 assetDecimals
    ) public view {
        assetDecimals = uint8(bound(assetDecimals, 6, 18));
        // when the balance becomes really small, the error on the final price becomes larger
        vaultBalance = uint128(bound(vaultBalance, 10 ** assetDecimals, type(uint128).max));
        assetPrice = uint128(bound(assetPrice, 0.01 ether, type(uint128).max));
        targetPrice = uint128(bound(targetPrice, 1 ether, 2 ether));
        uint256 newTotalSupply = protocol.i_calcRebaseTotalSupply(vaultBalance, assetPrice, targetPrice, assetDecimals);
        vm.assume(newTotalSupply > 0);
        uint256 newPrice = protocol.i_calcUsdnPrice(vaultBalance, assetPrice, newTotalSupply, assetDecimals);

        // Here we potentially have a small error, in part due to how the price results from the total supply, which
        // itself results from the division by the divisor. We can't expect the price to be exactly the target price.
        // Another part of the error comes from the potential difference in the number of decimals for the USDN token
        // and the asset token.
        assertApproxEqRel(newPrice, targetPrice, 0.0002 ether, "final price");
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
            expectedVaultBalance, newPrice, protocol.getTargetUsdnPrice(), protocol.getAssetDecimals()
        );
        uint256 expectedDivisor = usdn.totalSupply() * usdn.divisor() / expectedTotalSupply;

        // we do not need to wait for the rebase interval to pass because `liquidate` overrides the check

        // rebase (no liquidation happens)
        vm.expectEmit();
        emit Rebase(usdn.MAX_DIVISOR(), expectedDivisor);
        protocol.mockLiquidate(abi.encode(newPrice), 0);

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
        protocol.initiateDeposit(
            1 ether, address(this), payable(address(this)), NO_PERMIT2, abi.encode(newPrice), EMPTY_PREVIOUS_DATA
        );
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
        protocol.validateDeposit(payable(address(this)), abi.encode(newPrice), EMPTY_PREVIOUS_DATA);
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
        protocol.initiateWithdrawal(
            100 ether, address(this), payable(address(this)), abi.encode(newPrice), EMPTY_PREVIOUS_DATA
        );
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
        protocol.validateWithdrawal(payable(address(this)), abi.encode(newPrice), EMPTY_PREVIOUS_DATA);
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
        protocol.initiateOpenPosition(
            1 ether,
            params.initialPrice / 2,
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            abi.encode(newPrice),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Rebasing of the USDN token when validating a new long
     * @custom:given An initial USDN price of $1 and a long which was initiated
     * @custom:when The price of the asset is reduced by $100 and we call `validateOpenPosition`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenValidateOpenPosition() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.validateOpenPosition(payable(address(this)), abi.encode(newPrice), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario Rebasing of the USDN token when initiating a long closing
     * @custom:given An initial USDN price of $1
     * @custom:when The price of the asset is reduced by $100 and we call `initiateClosePosition`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenInitiateClosePosition() public {
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.initiateClosePosition(
            posId, 1 ether, address(this), payable(address(this)), abi.encode(newPrice), EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario Rebasing of the USDN token when validating a position closing
     * @custom:given An initial USDN price of $1 and a close position which was initiated
     * @custom:when The price of the asset is reduced by $100 and we call `validateClosePosition`
     * @custom:then The USDN token is rebased
     */
    function test_usdnRebaseWhenValidateClosePosition() public {
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: 1 ether,
                desiredLiqPrice: params.initialPrice / 2,
                price: params.initialPrice
            })
        );

        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals(), "initial price");

        uint128 newPrice = params.initialPrice - 100 ether;

        // we wait long enough to check for a rebase again
        skip(protocol.getUsdnRebaseInterval() + 1);

        // rebase
        vm.expectEmit(false, false, false, false);
        emit Rebase(0, 0);
        protocol.validateClosePosition(payable(address(this)), abi.encode(newPrice), EMPTY_PREVIOUS_DATA);
    }
}
