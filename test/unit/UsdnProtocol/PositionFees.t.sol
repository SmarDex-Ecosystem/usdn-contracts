// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";

import {
    Position,
    PendingAction,
    ProtocolAction,
    VaultPendingAction,
    LongPendingAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The entry/exit position fees mechanism of the protocol
 */
contract TestUsdnProtocolPositionFees is UsdnProtocolBaseFixture {
    uint256 internal constant INITIAL_WSTETH_BALANCE = 10_000 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.enablePositionFees = true;

        super._setUp(params);
        wstETH.mintAndApprove(address(this), INITIAL_WSTETH_BALANCE, address(protocol), type(uint256).max);
    }

    /* -------------------------------------------------------------------------- */
    /*                         Open / close long position                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates a position opening
     * @custom:given The price of the asset is $2000
     * @custom:and The leverage is x2
     * @custom:when The user initiates a position opening with 1 wstETH as collateral
     * @custom:then The protocol emit an event with the correct price including the fees
     * @custom:and The protocol emit an event with the correct leverage computed with the fees
     */
    function test_initiateOpenPosition() public {
        uint128 desiredLiqPrice = 2000 ether / 2;

        uint256 expectedPrice = 2000 ether + 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();
        uint256 expectedLeverage = protocol.i_getLeverage(
            uint128(expectedPrice),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(desiredLiqPrice)
                    - int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing()
            )
        );

        vm.recordLogs();

        bytes memory priceData = abi.encode(2000 ether);
        protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (, uint128 leverage,, uint256 price,,,) =
            abi.decode(logs[0].data, (uint40, uint128, uint128, uint128, int24, uint256, uint256));

        assertEq(logs[0].topics[0], InitiatedOpenPosition.selector);
        assertEq(price, expectedPrice, "assetPrice");
        assertEq(leverage, expectedLeverage, "leverage");
    }

    /**
     * @custom:scenario The user initiates and validate a position opening
     * @custom:given The price of the asset is $2000
     * @custom:and The leverage is x2
     * @custom:when The user initiates a position opening with 1 wstETH as collateral
     * @custom:and The user validate his position opening with the same price
     * @custom:then The protocol emit an event with the correct price with the fees
     * @custom:and The protocol emit an event with the correct leverage computed with the fees
     */
    function test_validateOpenPosition() public {
        skip(1 hours);

        uint128 desiredLiqPrice = 2000 ether / 2;

        bytes memory priceData = abi.encode(2000 ether);
        protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        // Wait at least 30 seconds to make sure liquidate updates the state
        skip(oracleMiddleware.getValidationDelay() + 30);

        // Call liquidate to trigger liquidation multiplier update
        protocol.liquidate(priceData, 0);

        uint256 expectedPrice = 2000 ether + 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();
        uint256 expectedLeverage = protocol.i_getLeverage(
            uint128(expectedPrice),
            protocol.getEffectivePriceForTick(
                protocol.getEffectiveTickForPrice(desiredLiqPrice)
                    - int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing()
            )
        );

        vm.recordLogs();

        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint128 leverage, uint256 price,,,) = abi.decode(logs[0].data, (uint128, uint128, int24, uint256, uint256));

        assertEq(logs[0].topics[0], ValidatedOpenPosition.selector);
        assertEq(price, expectedPrice, "assetPrice");
        assertEq(leverage, expectedLeverage, "leverage");
    }

    /**
     * @custom:scenario The user open a position and then initiate the position closing
     * @custom:given The price of the asset is $2000
     * @custom:and The leverage is x2
     * @custom:when The user initiates a position opening with 1 wstETH as collateral
     * @custom:and The user validate his position opening with the same price
     * @custom:and The user should be able to initiate a position closing
     * @custom:then The user pending position should have a start price according to the fees
     * @custom:and The user pending position should have a leverage according to the fees
     */
    function test_initiateClosePosition() public {
        skip(1 hours);

        uint128 desiredLiqPrice = 2000 ether / 2;

        bytes memory priceData = abi.encode(2000 ether);
        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(1 hours);

        // Call liquidate to trigger balance update
        protocol.liquidate(priceData, 0);

        uint256 storageBalanceBefore = protocol.getBalanceLong();

        protocol.initiateClosePosition(
            tick, tickVersion, index, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        uint256 expectedTempTransfer = protocol.i_assetToTransfer(
            uint128(2000 ether - 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()),
            tick,
            action.closeTotalExpo,
            protocol.getLiquidationMultiplier()
        );

        uint256 storageBalanceAfter = protocol.getBalanceLong();

        assertEq(action.closeTempTransfer, expectedTempTransfer, "Computed asset to transfer");
        assertEq(storageBalanceBefore - storageBalanceAfter, expectedTempTransfer, "Protocol balance");
    }

    /**
     * @custom:scenario The user open a position and then initiate the position closing
     * @custom:given The price of the asset is $2000
     * @custom:and The leverage is x2
     * @custom:when The user initiates a position opening with 1 wstETH as collateral
     * @custom:and The user validate his position opening with the same price
     * @custom:and The user initiates a position closing
     * @custom:and The user should be able to validate his position closing
     * @custom:then The user should receive the expected amount of wstETH according to the fees
     * @custom:and The emitted event should have the correct amount of wstETH to transfer according to the fees
     */
    function test_validateClosePosition() public {
        uint128 desiredLiqPrice = 2000 ether / 2;

        bytes memory priceData = abi.encode(2000 ether);
        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(1 hours);

        uint256 balanceBefore = wstETH.balanceOf(address(this));

        protocol.initiateClosePosition(
            tick, tickVersion, index, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        uint256 expectedTransfer = protocol.i_assetToTransfer(
            uint128(2000 ether - 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()),
            tick,
            action.closeTotalExpo,
            action.closeLiqMultiplier
        );

        skip(oracleMiddleware.getValidationDelay() + 1);
        vm.recordLogs();
        protocol.validateClosePosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (,,, uint256 assetToTransfer,) = abi.decode(logs[1].data, (int24, uint256, uint256, uint256, int256));

        assertEq(logs[1].topics[0], ValidatedClosePosition.selector);
        assertEq(wstETH.balanceOf(address(this)) - balanceBefore, expectedTransfer, "wstETH balance");
        assertEq(assetToTransfer, expectedTransfer, "Computed asset to transfer");
    }

    /* -------------------------------------------------------------------------- */
    /*                             Deposit / withdraw                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's position should have a start price according to the fees
     */
    function test_initiateDepositPositionFees() public {
        skip(1 hours);
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        VaultPendingAction memory action = protocol.i_toVaultPendingAction(protocol.getUserPendingAction(address(this)));

        uint256 priceWithoutFees =
            2000 ether - 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();
        assertEq(action.assetPrice, priceWithoutFees, "assetPrice");
    }

    /**
     * @custom:scenario The user validate a deposit of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user deposit 1 wstETH
     * @custom:then The user's position should have a start price according to the fees
     * @custom:and The minted USDN should be updated according to the fees
     */
    function test_validateDepositPositionFees() public {
        skip(1 hours);
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        uint256 expectedBalanceA = protocol.i_calcMintUsdn(
            depositAmount,
            protocol.getBalanceVault(),
            usdn.totalSupply(),
            2000 ether - 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()
        );

        skip(oracleMiddleware.getValidationDelay() + 1);

        PendingAction memory action = protocol.getUserPendingAction(address(this));
        VaultPendingAction memory deposit = protocol.i_toVaultPendingAction(action);

        // Check stored position asset price
        uint256 expectedBalanceB = protocol.i_calcMintUsdn(
            depositAmount,
            uint256(
                protocol.i_vaultAssetAvailable(
                    deposit.totalExpo,
                    deposit.balanceVault,
                    deposit.balanceLong,
                    uint128(2000 ether - 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()),
                    deposit.assetPrice
                )
            ),
            deposit.usdnTotalSupply,
            2000 ether - 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()
        );

        uint256 expectedBalance = expectedBalanceA < expectedBalanceB ? expectedBalanceA : expectedBalanceB;

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateDeposit(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));
        uint256 mintedUsdn = usdnBalanceAfter - usdnBalanceBefore;

        assertEq(mintedUsdn, expectedBalance, "Minted USDN");
    }

    /**
     * @custom:scenario The user initiates a withdraw of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user deposit 1 wstETH
     * @custom:and Withdraw the all minted USDN
     * @custom:then The user's position should have a start price according to the fees
     * @custom:and The minted USDN should be updated according to the fees
     * @custom:and The user's withdrawal pending position should have a start price according to the fees
     */
    function test_initiateWithdrawalPositionFees() public {
        skip(1 hours);
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(oracleMiddleware.getValidationDelay() + 1);

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateDeposit(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));
        uint256 mintedUsdn = usdnBalanceAfter - usdnBalanceBefore;

        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint128(mintedUsdn), currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        PendingAction memory action = protocol.getUserPendingAction(address(this));
        VaultPendingAction memory withdraw = protocol.i_toVaultPendingAction(action);

        // Check stored position asset price
        uint256 expectedPrice = 2000 ether + 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();
        assertEq(withdraw.assetPrice, expectedPrice, "assetPrice validate");
    }

    /**
     * @custom:scenario The user validate a withdraw of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:when The user deposit 1 wstETH
     * @custom:then The user's should send all the minted USDN to the protocol
     * @custom:and The user's should lose the expected amount of wstETH according to the fees
     */
    function test_validateWithdrawalPositionFees() public {
        skip(1 hours);
        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding
        uint256 initialAssetBalance = wstETH.balanceOf(address(this));

        protocol.initiateDeposit(depositAmount, currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(oracleMiddleware.getValidationDelay() + 1);

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateDeposit(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));
        uint256 mintedUsdn = usdnBalanceAfter - usdnBalanceBefore;

        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint128(mintedUsdn), currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateWithdrawal(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));
        usdnBalanceAfter = usdn.balanceOf(address(this));
        uint256 finalAssetBalance = wstETH.balanceOf(address(this));

        assertEq(usdnBalanceAfter, usdnBalanceBefore, "usdn balance withdraw");
        assertLt(finalAssetBalance, initialAssetBalance, "wstETH balance before and after");
    }

    /* -------------------------------------------------------------------------- */
    /*                        Compare with and without fees                       */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user validate the same deposit one time with fees and one time without fees
     * @custom:given The price of the asset is $2000
     * @custom:when The user validate a deposit of 1 wstETH with fees
     * @custom:and The user validate a deposit of 1 wstETH without fees
     * @custom:then The USDN minted without fees should be greater than the USDN minted with fees
     */
    function test_validateDepositPositionFeesCompareWithAndWithoutFees() public {
        skip(1 hours);
        usdn.approve(address(protocol), type(uint256).max);
        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));

        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        uint256 snapshotId = vm.snapshot();

        /* ----------------------- Validate with position fees ---------------------- */
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        protocol.initiateDeposit(depositAmount, currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateDeposit(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));
        uint256 usdnBalanceAfterWithoutFees = usdn.balanceOf(address(this));

        uint256 mintedUsdnWithoutFees = usdnBalanceAfterWithoutFees - usdnBalanceBefore;

        /* ----------------------- Validate with position fees ---------------------- */
        vm.revertTo(snapshotId);

        vm.prank(ADMIN);
        protocol.setPositionFeeBps(100); // 1% fees

        protocol.initiateDeposit(depositAmount, currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateDeposit(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));
        uint256 usdnBalanceAfterWithFees = usdn.balanceOf(address(this));

        uint256 mintedUsdnWithFees = usdnBalanceAfterWithFees - usdnBalanceBefore;

        // Check if the amount of usdn minted with fees is less than the amount minted without fees

        assertLt(mintedUsdnWithFees, mintedUsdnWithoutFees, "Minted USDN");
    }

    /**
     * @custom:scenario The user validate the same withdraw one time with fees and one time without fees
     * @custom:given The price of the asset is $2000
     * @custom:when The user validate a withdraw of a 1 wstETH deposit with fees
     * @custom:and The user validate a withdraw of a 1 wstETH deposit without fees
     * @custom:then The asset received with fees should be lower than the asset received without fees
     */
    function test_validateWithdrawalPositionFeesCompareWithAndWithoutFees() public {
        /* ----------------------- Validate with position fees ---------------------- */
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        usdn.approve(address(protocol), type(uint256).max);

        uint128 depositAmount = 1 ether;
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply PnL + funding

        protocol.initiateDeposit(depositAmount, currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));
        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateDeposit(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        // Store the snapshot id to revert to this point after the next test
        uint256 snapshotId = vm.snapshot();

        uint256 initialAssetBalance = wstETH.balanceOf(address(this));

        vm.prank(ADMIN);
        protocol.setPositionFeeBps(100); // 1% fees

        protocol.initiateWithdrawal(
            uint128(usdn.balanceOf(address(this))), currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateWithdrawal(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        uint256 finalAssetBalance = wstETH.balanceOf(address(this));
        uint256 balanceDiffWithFees = finalAssetBalance - initialAssetBalance;

        /* --------------------- Validate without position fees --------------------- */
        vm.revertTo(snapshotId);

        protocol.initiateWithdrawal(
            uint128(usdn.balanceOf(address(this))), currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateWithdrawal(currentPrice, PreviousActionsData(new bytes[](0), new uint128[](0)));

        uint256 finalAssetBalanceWithoutFees = wstETH.balanceOf(address(this));
        uint256 balanceDiffWithoutFees = finalAssetBalanceWithoutFees - initialAssetBalance;

        assertLt(balanceDiffWithFees, balanceDiffWithoutFees, "Withdraw wstETH");
    }

    /**
     * @custom:scenario The user open a position one time with fees and one time without fees
     * @custom:given The price of the asset is $2000
     * @custom:when The user open a position with 1 wstETH as collateral, with fees
     * @custom:and The user open a position with 1 wstETH as collateral, without fees
     * @custom:then The pending position price with fees should be greater than the pending position price without
     * fees
     */
    function test_openPositionFeesCompareWithAndWithoutFees() public {
        skip(1 hours);

        uint128 desiredLiqPrice = 2000 ether / 2;
        bytes memory priceData = abi.encode(2000 ether);

        uint256 snapshotId = vm.snapshot();

        /* --------------------- Validate without position fees --------------------- */
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        skip(1 hours);

        protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        vm.recordLogs();

        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        Vm.Log[] memory logsWithoutFees = vm.getRecordedLogs();
        (, uint256 priceWithoutFees,,,) =
            abi.decode(logsWithoutFees[0].data, (uint128, uint128, int24, uint256, uint256));
        assertEq(logsWithoutFees[0].topics[0], ValidatedOpenPosition.selector);

        /* ----------------------- Validate with position fees ---------------------- */
        vm.revertTo(snapshotId);

        vm.prank(ADMIN);
        protocol.setPositionFeeBps(100); // 1% fees

        skip(1 hours);

        protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        vm.recordLogs();

        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        Vm.Log[] memory logsWithFees = vm.getRecordedLogs();
        (, uint256 priceWithFees,,,) = abi.decode(logsWithFees[0].data, (uint128, uint128, int24, uint256, uint256));
        assertEq(logsWithFees[0].topics[0], ValidatedOpenPosition.selector);

        // Check if the price with fees is greater than the price without fees
        assertGt(priceWithFees, priceWithoutFees, "Price with fees");
    }

    /**
     * @custom:scenario The user close a position one time with fees and one time without fees
     * @custom:given The price of the asset is $2000
     * @custom:when The user open and close a position with 1 wstETH as collateral, with fees
     * @custom:and The user open and close a position with 1 wstETH as collateral, without fees
     * @custom:then The asset received with fees should be lower than the asset received without fees
     * @custom:and The emitted event should have the correct amount of wstETH to transfer according to the fees
     */
    function test_closePositionFeesCompareWithAndWithoutFees() public {
        skip(1 hours);

        uint128 desiredLiqPrice = 2000 ether / 2;
        bytes memory priceData = abi.encode(2000 ether);

        uint256 snapshotId = vm.snapshot();

        /* ----------------------- Validate with position fees ---------------------- */
        vm.prank(ADMIN);
        protocol.setPositionFeeBps(0); // 0% fees

        (int24 tick, uint256 tickVersion, uint256 index) = protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(1 hours);

        protocol.initiateClosePosition(
            tick, tickVersion, index, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        skip(oracleMiddleware.getValidationDelay() + 1);

        uint256 balanceBeforeValidateWithoutFees = wstETH.balanceOf(address(this));

        vm.recordLogs();
        protocol.validateClosePosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (,,, uint256 assetToTransferWithoutFees,) = abi.decode(logs[1].data, (int24, uint256, uint256, uint256, int256));
        uint256 assetTransferredWithoutFees = wstETH.balanceOf(address(this)) - balanceBeforeValidateWithoutFees;
        assertEq(logs[1].topics[0], ValidatedClosePosition.selector);

        /* ----------------------- Validate with position fees ---------------------- */
        vm.revertTo(snapshotId);

        vm.prank(ADMIN);
        protocol.setPositionFeeBps(100); // 1% fees

        (tick, tickVersion, index) = protocol.initiateOpenPosition(
            1 ether, desiredLiqPrice, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );
        skip(oracleMiddleware.getValidationDelay() + 1);

        protocol.validateOpenPosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));

        skip(1 hours);

        protocol.initiateClosePosition(
            tick, tickVersion, index, priceData, PreviousActionsData(new bytes[](0), new uint128[](0))
        );

        action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        skip(oracleMiddleware.getValidationDelay() + 1);

        uint256 balanceBeforeValidateWithFees = wstETH.balanceOf(address(this));

        vm.recordLogs();
        protocol.validateClosePosition(priceData, PreviousActionsData(new bytes[](0), new uint128[](0)));
        logs = vm.getRecordedLogs();

        (,,, uint256 assetToTransferWithFees,) = abi.decode(logs[1].data, (int24, uint256, uint256, uint256, int256));
        uint256 assetTransferredWithFees = wstETH.balanceOf(address(this)) - balanceBeforeValidateWithFees;
        assertEq(logs[1].topics[0], ValidatedClosePosition.selector);

        /* --------------------------------- Checks --------------------------------- */

        // Check if the transferred asset with fees is less than the transferred asset without fees
        assertLt(assetToTransferWithFees, assetToTransferWithoutFees, "Transferred asset");

        // Same check for the emitted event
        assertLt(assetTransferredWithFees, assetTransferredWithoutFees, "Transferred asset");
    }
}
