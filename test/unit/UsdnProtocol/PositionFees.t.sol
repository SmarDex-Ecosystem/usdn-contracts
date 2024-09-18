// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Vm } from "forge-std/Vm.sol";

import { ADMIN } from "../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";

import { UsdnProtocolUtilsLibrary as Utils } from "../../../src/UsdnProtocol/libraries/UsdnProtocolUtilsLibrary.sol";

/**
 * @custom:feature The entry/exit position fees mechanism of the protocol
 */
contract TestUsdnProtocolPositionFees is UsdnProtocolBaseFixture {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enablePositionFees = true;
        super._setUp(params);
    }

    struct ExpectedData {
        uint256 expectedPrice;
        int24 expectedTick;
        uint128 effectiveTickPrice;
        uint128 expectedPosTotalExpo;
        uint256 expectedPositionValue;
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
     * @custom:and The protocol emit an event with the correct total expo computed with the fees
     */
    function test_initiateOpenPosition() public {
        uint128 currentPrice = 2000 ether;
        uint128 desiredLiqPrice = currentPrice / 2;
        uint128 amount = 1 ether;

        ExpectedData memory expected;
        expected.expectedPrice =
            currentPrice + currentPrice * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();
        expected.expectedTick = protocol.getEffectiveTickForPrice(desiredLiqPrice);

        // Price without the liquidation penalty
        uint128 effectiveTickPrice =
            protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(expected.expectedTick));
        expected.expectedPosTotalExpo =
            protocol.i_calcPositionTotalExpo(amount, uint128(expected.expectedPrice), effectiveTickPrice);
        expected.expectedPositionValue =
            uint256(expected.expectedPosTotalExpo) * (currentPrice - effectiveTickPrice) / currentPrice;

        uint256 longBalanceBefore = protocol.getBalanceLong();
        uint256 vaultBalanceBefore = protocol.getBalanceVault();
        wstETH.mintAndApprove(address(this), amount, address(protocol), amount);
        vm.recordLogs();

        bytes memory priceData = abi.encode(currentPrice);
        (, PositionId memory posId) = protocol.initiateOpenPosition(
            amount,
            desiredLiqPrice,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            NO_PERMIT2,
            priceData,
            EMPTY_PREVIOUS_DATA
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[1].topics[0], InitiatedOpenPosition.selector);

        (, uint128 posTotalExpo,, uint256 price,,,) =
            abi.decode(logs[1].data, (uint40, uint128, uint128, uint128, int24, uint256, uint256));

        assertEq(price, expected.expectedPrice, "assetPrice");
        assertEq(posTotalExpo, expected.expectedPosTotalExpo, "posTotalExpo");
        assertEq(
            protocol.getPositionValue(posId, currentPrice, uint128(block.timestamp)),
            int256(expected.expectedPositionValue),
            "position value"
        );
        assertEq(protocol.getBalanceLong(), longBalanceBefore + expected.expectedPositionValue, "balance long");
        assertEq(
            protocol.getBalanceLong() + protocol.getBalanceVault(),
            longBalanceBefore + vaultBalanceBefore + amount,
            "total balance"
        );
    }

    /**
     * @custom:scenario The user initiates and validate a position opening
     * @custom:given The price of the asset is $2000
     * @custom:and The leverage is x2
     * @custom:when The user initiates a position opening with 1 wstETH as collateral
     * @custom:and The user validate his position opening with the same price
     * @custom:then The protocol emit an event with the correct price with the fees
     * @custom:and The protocol emit an event with the correct total expo computed with the fees
     */
    function test_validateOpenPosition() public {
        uint128 currentPrice = 2000 ether;
        uint128 desiredLiqPrice = currentPrice / 2;
        bytes memory priceData = abi.encode(currentPrice);
        uint128 amount = 1 ether;

        uint256 longBalanceBefore = protocol.getBalanceLong();
        uint256 vaultBalanceBefore = protocol.getBalanceVault();

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: amount,
                desiredLiqPrice: desiredLiqPrice,
                price: currentPrice
            })
        );

        // Wait at least 30 seconds additionally to make sure liquidate updates the state
        _waitBeforeLiquidation();

        // Call liquidate to trigger liquidation multiplier update
        protocol.mockLiquidate(priceData);

        ExpectedData memory expected;
        // Price without the liquidation penalty
        uint128 effectiveTickPrice = protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick));
        expected.expectedPrice =
            currentPrice + currentPrice * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR();
        expected.expectedPosTotalExpo =
            protocol.i_calcPositionTotalExpo(amount, uint128(expected.expectedPrice), effectiveTickPrice);
        expected.expectedPositionValue =
            uint256(expected.expectedPosTotalExpo) * (currentPrice - effectiveTickPrice) / currentPrice;

        vm.recordLogs();

        protocol.validateOpenPosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint128 posTotalExpo, uint256 price,,,) = abi.decode(logs[0].data, (uint128, uint128, int24, uint256, uint256));

        assertEq(logs[0].topics[0], ValidatedOpenPosition.selector);
        assertEq(price, expected.expectedPrice, "assetPrice");
        assertEq(posTotalExpo, expected.expectedPosTotalExpo, "posTotalExpo");
        assertEq(
            protocol.getPositionValue(posId, currentPrice, uint128(block.timestamp)),
            int256(expected.expectedPositionValue),
            "position value"
        );
        assertEq(protocol.getBalanceLong(), longBalanceBefore + expected.expectedPositionValue, "balance long");
        assertEq(
            protocol.getBalanceLong() + protocol.getBalanceVault(),
            longBalanceBefore + vaultBalanceBefore + amount,
            "total balance"
        );
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
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );
        skip(1 hours);

        uint256 balanceBefore = wstETH.balanceOf(address(this));

        protocol.initiateClosePosition(
            posId, 1 ether, DISABLE_MIN_PRICE, address(this), payable(address(this)), priceData, EMPTY_PREVIOUS_DATA
        );

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        uint256 expectedTransfer = uint256(
            protocol.i_positionValue(
                uint128(2000 ether - 2000 ether * uint256(protocol.getPositionFeeBps()) / protocol.BPS_DIVISOR()),
                protocol.i_getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick), action.liqMultiplier),
                action.closePosTotalExpo
            )
        );

        _waitDelay();
        vm.recordLogs();
        protocol.validateClosePosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        (,,, uint256 assetToTransfer,) = abi.decode(logs[2].data, (int24, uint256, uint256, uint256, int256));

        assertEq(logs[2].topics[0], ValidatedClosePosition.selector);
        assertEq(wstETH.balanceOf(address(this)) - balanceBefore, expectedTransfer, "wstETH balance");
        assertEq(assetToTransfer, expectedTransfer, "Computed asset to transfer");
    }

    /* -------------------------------------------------------------------------- */
    /*                             Deposit / withdraw                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario The user initiates a deposit of 1 wstETH
     * @custom:when The user initiates a deposit of 1 wstETH
     * @custom:then The user's position should have an amount corresponding to the deposited amount
     * @custom:and The fee should match the vault fee
     */
    function test_initiateDepositPositionFees() public {
        skip(1 hours);
        uint128 depositAmount = 1 ether;
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, depositAmount, 2000 ether);

        DepositPendingAction memory action =
            protocol.i_toDepositPendingAction(protocol.getUserPendingAction(address(this)));

        assertEq(action.amount, depositAmount, "amount");
        assertEq(action.feeBps, protocol.getVaultFeeBps(), "fee");
    }

    /**
     * @custom:scenario The user validates a deposit of 1 wstETH
     * @custom:given The user initiated the deposit of 1 wstETH
     * @custom:when The user validates the deposit
     * @custom:then The minted USDN should match the amount with fees
     */
    function test_validateDepositPositionFees() public {
        skip(1 hours);
        uint128 depositAmount = 1 ether;
        uint128 price = 2000 ether;
        bytes memory priceData = abi.encode(price); // only used to apply funding

        uint128 initialBlock = uint128(block.timestamp);
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, depositAmount, price);

        uint128 amountAfterFees =
            uint128(depositAmount - uint256(depositAmount) * protocol.getVaultFeeBps() / protocol.BPS_DIVISOR());
        uint256 expectedSharesBalanceA = Utils._calcMintUsdnShares(
            amountAfterFees, uint256(protocol.vaultAssetAvailableWithFunding(price, initialBlock)), usdn.totalShares()
        );

        _waitDelay();

        PendingAction memory action = protocol.getUserPendingAction(address(this));
        DepositPendingAction memory deposit = protocol.i_toDepositPendingAction(action);

        // Check stored position asset price
        uint256 expectedSharesBalanceB = Utils._calcMintUsdnShares(
            amountAfterFees,
            uint256(
                protocol.i_vaultAssetAvailable(
                    deposit.totalExpo, deposit.balanceVault, deposit.balanceLong, price, deposit.assetPrice
                )
            ),
            deposit.usdnTotalShares
        );

        uint256 expectedSharesBalance =
            expectedSharesBalanceA < expectedSharesBalanceB ? expectedSharesBalanceA : expectedSharesBalanceB;
        uint256 expectedBalance = usdn.convertToTokens(expectedSharesBalance);

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        uint256 usdnSharesBefore = usdn.sharesOf(address(this));
        protocol.validateDeposit(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));
        uint256 usdnSharesAfter = usdn.sharesOf(address(this));
        uint256 mintedUsdn = usdnBalanceAfter - usdnBalanceBefore;
        uint256 mintedShares = usdnSharesAfter - usdnSharesBefore;

        assertEq(mintedUsdn, expectedBalance, "Minted USDN");
        assertEq(mintedShares, expectedSharesBalance, "Minted USDN Shares");
    }

    /**
     * @custom:scenario The user initiates a withdraw of 1 wstETH
     * @custom:given The price of the asset is $2000
     * @custom:and The user deposited 1 wstETH
     * @custom:when The user initiates a withdrawal
     * @custom:then The pending action fee matches the vault fee
     */
    function test_initiateWithdrawalPositionFees() public {
        skip(1 hours);
        uint128 depositAmount = 1 ether;
        uint128 price = 2000 ether;

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, depositAmount, price);
        uint256 mintedUsdn = usdn.balanceOf(address(this)) - usdnBalanceBefore;

        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint128(mintedUsdn),
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(price),
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        WithdrawalPendingAction memory withdraw = protocol.i_toWithdrawalPendingAction(action);

        assertEq(withdraw.feeBps, protocol.getVaultFeeBps(), "feeBps");
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
        bytes memory currentPrice = abi.encode(uint128(2000 ether)); // only used to apply funding
        uint256 initialAssetBalance = wstETH.balanceOf(address(this));

        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, depositAmount, 2000 ether);

        uint256 usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateDeposit(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
        uint256 usdnBalanceAfter = usdn.balanceOf(address(this));
        uint256 mintedUsdn = usdnBalanceAfter - usdnBalanceBefore;

        usdn.approve(address(protocol), type(uint256).max);
        protocol.initiateWithdrawal(
            uint128(mintedUsdn),
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        usdnBalanceBefore = usdn.balanceOf(address(this));
        protocol.validateWithdrawal(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);
        usdnBalanceAfter = usdn.balanceOf(address(this));
        uint256 finalAssetBalance = wstETH.balanceOf(address(this));

        assertEq(usdnBalanceAfter, usdnBalanceBefore, "usdn balance withdraw");
        assertLt(finalAssetBalance - initialAssetBalance, depositAmount, "wstETH balance minus fees");
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

        uint256 snapshotId = vm.snapshot();

        /* ----------------------- Validate with position fees ---------------------- */
        vm.prank(ADMIN);
        protocol.setVaultFeeBps(0); // 0% fees
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, depositAmount, 2000 ether);
        uint256 usdnBalanceAfterWithoutFees = usdn.balanceOf(address(this));

        uint256 mintedUsdnWithoutFees = usdnBalanceAfterWithoutFees - usdnBalanceBefore;

        /* ----------------------- Validate with position fees ---------------------- */
        vm.revertTo(snapshotId);

        vm.prank(ADMIN);
        protocol.setVaultFeeBps(100); // 1% fees
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, depositAmount, 2000 ether);
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
        protocol.setVaultFeeBps(0); // 0% fees

        usdn.approve(address(protocol), type(uint256).max);

        uint128 depositAmount = 1 ether;
        uint128 price = 2000 ether;
        bytes memory currentPrice = abi.encode(price); // only used to apply PnL + funding

        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, depositAmount, price);

        // Store the snapshot id to revert to this point after the next test
        uint256 snapshotId = vm.snapshot();

        uint256 initialAssetBalance = wstETH.balanceOf(address(this));

        vm.prank(ADMIN);
        protocol.setVaultFeeBps(100); // 1% fees

        protocol.initiateWithdrawal(
            uint128(usdn.sharesOf(address(this))),
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateWithdrawal(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);

        uint256 finalAssetBalance = wstETH.balanceOf(address(this));
        uint256 balanceDiffWithFees = finalAssetBalance - initialAssetBalance;

        /* --------------------- Validate without position fees --------------------- */
        vm.revertTo(snapshotId);

        protocol.initiateWithdrawal(
            uint128(usdn.sharesOf(address(this))),
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateWithdrawal(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);

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

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        vm.recordLogs();
        protocol.validateOpenPosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        Vm.Log[] memory logsWithoutFees = vm.getRecordedLogs();
        (, uint256 priceWithoutFees,,,) =
            abi.decode(logsWithoutFees[1].data, (uint128, uint128, int24, uint256, uint256));
        assertEq(logsWithoutFees[1].topics[0], ValidatedOpenPosition.selector);

        /* ----------------------- Validate with position fees ---------------------- */
        vm.revertTo(snapshotId);

        vm.prank(ADMIN);
        protocol.setPositionFeeBps(100); // 1% fees

        skip(1 hours);

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        vm.recordLogs();
        protocol.validateOpenPosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);

        Vm.Log[] memory logsWithFees = vm.getRecordedLogs();
        (, uint256 priceWithFees,,,) = abi.decode(logsWithFees[1].data, (uint128, uint128, int24, uint256, uint256));
        assertEq(logsWithFees[1].topics[0], ValidatedOpenPosition.selector);

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

        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );

        skip(1 hours);

        protocol.initiateClosePosition(
            posId, 1 ether, DISABLE_MIN_PRICE, address(this), payable(address(this)), priceData, EMPTY_PREVIOUS_DATA
        );

        LongPendingAction memory action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        _waitDelay();

        uint256 balanceBeforeValidateWithoutFees = wstETH.balanceOf(address(this));

        vm.recordLogs();
        protocol.validateClosePosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (,,, uint256 assetToTransferWithoutFees,) = abi.decode(logs[2].data, (int24, uint256, uint256, uint256, int256));
        uint256 assetTransferredWithoutFees = wstETH.balanceOf(address(this)) - balanceBeforeValidateWithoutFees;
        assertEq(logs[2].topics[0], ValidatedClosePosition.selector);

        /* ----------------------- Validate with position fees ---------------------- */
        vm.revertTo(snapshotId);

        vm.prank(ADMIN);
        protocol.setPositionFeeBps(100); // 1% fees

        posId = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: 2000 ether
            })
        );
        skip(1 hours);

        protocol.initiateClosePosition(
            posId, 1 ether, DISABLE_MIN_PRICE, address(this), payable(address(this)), priceData, EMPTY_PREVIOUS_DATA
        );

        action = protocol.i_toLongPendingAction(protocol.getUserPendingAction(address(this)));

        _waitDelay();

        uint256 balanceBeforeValidateWithFees = wstETH.balanceOf(address(this));

        vm.recordLogs();
        protocol.validateClosePosition(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);
        logs = vm.getRecordedLogs();

        (,,, uint256 assetToTransferAfterFees,) = abi.decode(logs[2].data, (int24, uint256, uint256, uint256, int256));
        uint256 assetTransferredWithFees = wstETH.balanceOf(address(this)) - balanceBeforeValidateWithFees;
        assertEq(logs[2].topics[0], ValidatedClosePosition.selector);

        /* --------------------------------- Checks --------------------------------- */

        // Check if the transferred asset with fees is less than the transferred asset without fees
        assertLt(assetToTransferAfterFees, assetToTransferWithoutFees, "Transferred asset");

        // Same check for the emitted event
        assertLt(assetTransferredWithFees, assetTransferredWithoutFees, "Transferred asset");
    }
}
