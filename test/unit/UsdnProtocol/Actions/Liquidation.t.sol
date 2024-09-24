// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { DEPLOYER, USER_1 } from "../../../utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { InitializableReentrancyGuard } from "../../../../src/utils/InitializableReentrancyGuard.sol";

/// @custom:feature The scenarios in `UsdnProtocolActions` which call `_liquidatePositions`
contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    /// @notice Trigger a reentrancy after receiving ether
    bool internal _reenter;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);

        usdn.approve(address(protocol), type(uint256).max);

        vm.fee(30 gwei);
        vm.txGasPrice(32 gwei);
    }

    /* -------------------------------------------------------------------------- */
    /*                        Liquidations on Vault actions                       */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario User initiates a deposit after a price drawdown that liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and Price drops below its liquidation price
     * @custom:when User 2 initiates a deposit
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnInitiateDeposit() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // next deposit will only update the _lastPrice if it's more recent, and the on-chain price is 30 minutes old
        skip(31 minutes);

        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posId.tick);

        wstETH.mintAndApprove(address(this), 1 ether, address(protocol), 1 ether);
        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posId.tick, posId.tickVersion, 0, 0, 0);
        protocol.initiateDeposit(
            1 ether,
            DISABLE_SHARES_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(effectivePriceForTick),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario User validates a deposit after a price drawdown that liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and User 2 initiates a deposit
     * @custom:and Price drops below User 1's liquidation price
     * @custom:when User 2 validates its pending deposit
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnValidateDeposit() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // Initiates the deposit for the other user
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 1 ether, price);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posId.tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posId.tick, posId.tickVersion, 0, 0, 0);

        protocol.validateDeposit(payable(address(this)), abi.encode(effectivePriceForTick), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario User initiates a withdrawal after a price drawdown that liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and User 2 initiates and validates a deposit
     * @custom:and Price drops below User 1's liquidation price
     * @custom:when User 2 initiates a withdrawal
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnInitiateWithdrawal() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // Initiate and validate the deposit for the other user
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, price);

        // next deposit will only update the _lastPrice if it's more recent, and the on-chain price is 30 minutes old
        skip(31 minutes);

        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posId.tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posId.tick, posId.tickVersion, 0, 0, 0);

        protocol.initiateWithdrawal(
            uint128(usdn.balanceOf(address(this))),
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            abi.encode(effectivePriceForTick),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario User validates a withdrawal after a price drawdown that liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and User 2 initiates and validates a deposit, then initiates a withdrawal
     * @custom:and Price drops below its liquidation price
     * @custom:when User 2 validates its pending withdrawal action
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnValidateWithdrawal() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // Initiate and validate the deposit, then initiate the withdrawal for the other user
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateWithdrawal, 1 ether, price);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posId.tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posId.tick, posId.tickVersion, 0, 0, 0);

        protocol.validateWithdrawal(payable(address(this)), abi.encode(effectivePriceForTick), EMPTY_PREVIOUS_DATA);
    }

    /* -------------------------------------------------------------------------- */
    /*                        Liquidations on Long actions                        */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario User initiates an open position action after a price drawdown that
     * liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and Price drops below its liquidation price
     * @custom:when User 2 initiates an open position
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnInitiateOpenPosition() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // next deposit will only update the _lastPrice if it's more recent, and the on-chain price is 30 minutes old
        skip(31 minutes);

        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posId.tick);

        wstETH.mintAndApprove(address(this), 1 ether, address(protocol), 1 ether);
        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posId.tick, posId.tickVersion, 0, 0, 0);
        protocol.initiateOpenPosition(
            1 ether,
            desiredLiqPrice - 200 ether,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            abi.encode(effectivePriceForTick),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario User validates an open position after a price drawdown that
     * liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and User 2 initiates an open position
     * @custom:and Price drops below User 1's liquidation price
     * @custom:when User 2 validates its pending open position
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnValidateOpenPosition() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // Initiates the position for the other user
        price -= 200 ether;
        desiredLiqPrice -= 200 ether;
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posId.tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posId.tick, posId.tickVersion, 0, 0, 0);
        protocol.validateOpenPosition(payable(address(this)), abi.encode(effectivePriceForTick), EMPTY_PREVIOUS_DATA);
    }

    /**
     * @custom:scenario User initiates a close position action after a price drawdown that
     * liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and User 2 initiates and validates an open position
     * @custom:and Price drops below User 1's liquidation price
     * @custom:when User 2 initiates a close position action
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnInitiateClosePosition() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posIdToLiquidate = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // Initiates and validates the position for the other user
        desiredLiqPrice -= 200 ether;
        PositionId memory posIdToClose = setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // next deposit will only update the _lastPrice if it's more recent, and the on-chain price is 30 minutes old
        skip(31 minutes);

        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posIdToLiquidate.tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posIdToLiquidate.tick, posIdToLiquidate.tickVersion, 0, 0, 0);

        protocol.initiateClosePosition(
            posIdToClose,
            1 ether,
            DISABLE_MIN_PRICE,
            address(this),
            payable(address(this)),
            abi.encode(effectivePriceForTick),
            EMPTY_PREVIOUS_DATA
        );
    }

    /**
     * @custom:scenario User close his position action after a price drawdown that
     * liquidates underwater long positions.
     * @custom:given User 1 opens a position
     * @custom:and User 2 initiates and validates an open position
     * @custom:and User 2 initiates a close position action
     * @custom:and Price drops below User 1's liquidation price
     * @custom:when User 2 initiates a close position action
     * @custom:then It should liquidate User 1's position.
     */
    function test_userLiquidatesOnValidateClosePosition() public {
        uint256 price = 2000 ether;
        uint128 desiredLiqPrice = uint128(price) - 200 ether;

        // Create a long position to liquidate
        PositionId memory posIdToLiquidate = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // Initiates and validates the position for the other user
        desiredLiqPrice -= 200 ether;
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.InitiateClosePosition,
                positionSize: 1 ether,
                desiredLiqPrice: desiredLiqPrice,
                price: price
            })
        );

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(posIdToLiquidate.tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(posIdToLiquidate.tick, posIdToLiquidate.tickVersion, 0, 0, 0);

        protocol.validateClosePosition(payable(address(this)), abi.encode(effectivePriceForTick), EMPTY_PREVIOUS_DATA);
    }

    /* -------------------------------------------------------------------------- */
    /*                        Liquidations from liquidate()                       */
    /* -------------------------------------------------------------------------- */

    /**
     * @custom:scenario A liquidator receives no rewards if liquidate() is called but no ticks can be liquidated
     * @custom:given There are no ticks that can be liquidated
     * @custom:when A liquidator calls the function liquidate()
     * @custom:then No rewards are sent and no ticks are liquidated
     */
    function test_nothingHappensIfNoTicksCanBeLiquidated() public {
        bytes memory priceData = abi.encode(2000 ether);

        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: 1700 ether,
                price: 2000 ether
            })
        );

        priceData = abi.encode(1950 ether);

        uint256 wstETHBalanceBeforeRewards = wstETH.balanceOf(address(this));
        uint256 balanceBeforeRewards = protocol.getBalanceVault() + protocol.getBalanceLong();
        assertEq(balanceBeforeRewards, wstETH.balanceOf(address(protocol)), "protocol total balance");
        uint256 longPositionsBeforeLiquidation = protocol.getTotalLongPositions();

        _waitBeforeLiquidation();
        LiqTickInfo[] memory liquidatedTicks = protocol.mockLiquidate(priceData, 1);

        assertEq(liquidatedTicks.length, 0, "No position should have been liquidated");

        // Check that the liquidator didn't receive any rewards
        assertEq(
            wstETHBalanceBeforeRewards,
            wstETH.balanceOf(address(this)),
            "The liquidator should not receive rewards if there were no liquidations"
        );

        // Check that the total balance did not change
        assertEq(
            balanceBeforeRewards,
            protocol.getBalanceVault() + protocol.getBalanceLong(),
            "The total balance should not change if there were no liquidations"
        );

        // Check if first total long positions match initial value
        assertEq(
            longPositionsBeforeLiquidation,
            protocol.getTotalLongPositions(),
            "The number of long positions should not have changed"
        );
    }

    /**
     * @custom:scenario A liquidator liquidate a tick and receive a reward
     * @custom:given There is a tick that can be liquidated
     * @custom:when A liquidator calls the function liquidate()
     * @custom:then The tick is liquidated
     * @custom:and The protocol send rewards for the liquidation
     */
    function test_canLiquidateAndReceiveReward() public {
        uint128 price = 2000 ether;

        // Setup a long position from another user
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: 1700 ether,
                price: price
            })
        );

        // Change The rewards calculations parameters to not be dependent of the initial values
        vm.prank(DEPLOYER);
        liquidationRewardsManager.setRewardsParameters(
            10_000, 30_000, 20_000, 20_000, 10 gwei, 15_000, 500, 0.1 ether, 1 ether
        );

        // Get the proper liquidation price for the tick
        price = protocol.getEffectivePriceForTick(posId.tick);
        int256 collateralLiquidated = protocol.i_tickValue(
            posId.tick,
            price,
            protocol.getLongTradingExpo(price),
            protocol.getLiqMultiplierAccumulator(),
            protocol.getTickData(posId.tick)
        );
        (Position memory position, uint24 penalty) = protocol.getLongPosition(posId);

        LiqTickInfo[] memory liquidatedTicks = new LiqTickInfo[](1);
        liquidatedTicks[0] = LiqTickInfo({
            totalPositions: 1,
            totalExpo: position.totalExpo,
            remainingCollateral: collateralLiquidated,
            tickPrice: price,
            priceWithoutPenalty: protocol.getEffectivePriceForTick(protocol.i_calcTickWithoutPenalty(posId.tick, penalty))
        });
        uint256 expectedLiquidatorRewards = liquidationRewardsManager.getLiquidationRewards(
            liquidatedTicks, price, false, RebalancerAction.None, ProtocolAction.None, "", ""
        );
        // Sanity check
        assertGt(expectedLiquidatorRewards, 0, "The expected liquidation rewards should be greater than 0");

        uint256 wstETHBalanceBeforeRewards = wstETH.balanceOf(address(this));

        int256 vaultAssetAvailable = protocol.i_vaultAssetAvailable(price);

        _waitBeforeLiquidation();
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        liquidatedTicks = protocol.mockLiquidate(abi.encode(price), 1);

        // Check that the right number of positions have been liquidated
        assertEq(liquidatedTicks.length, 1, "One position should have been liquidated");

        // Check that the liquidator received its rewards
        assertEq(
            wstETH.balanceOf(address(this)) - wstETHBalanceBeforeRewards,
            expectedLiquidatorRewards,
            "The liquidator did not receive the right amount of rewards"
        );
        // Check that the vault balance got updated
        assertEq(
            protocol.getBalanceVault(),
            uint256(vaultAssetAvailable) + uint256(collateralLiquidated) - expectedLiquidatorRewards,
            "The vault does not contain the right amount of funds"
        );
    }

    /**
     * @custom:scenario A liquidator liquidate a tick and receive a reward but the vault doesn't have enough balance
     * @custom:given There is a tick that can be liquidated
     * @custom:and The vault doesn't have enough assets to cover the liquidator rewards
     * @custom:when A liquidator calls the function liquidate()
     * @custom:then The tick is liquidated
     * @custom:and The protocol send rewards for the liquidation based on what's left in the vault
     */
    function test_canLiquidateAndReceiveRewardsUpToTheVaultBalance() public {
        uint128 initialPrice = params.initialPrice;
        uint128 endPrice = 1700 ether;

        // Setup a long position from another user
        PositionId memory posId = setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: endPrice,
                price: initialPrice
            })
        );

        // Change The rewards calculations parameters to not be dependent of the initial values
        vm.prank(DEPLOYER);
        // Put incredibly high values to empty the vault
        liquidationRewardsManager.setRewardsParameters(
            500_000, 1_000_000, 200_000, 200_000, 100 gwei, type(uint16).max, type(uint16).max, 100 ether, 1000 ether
        );

        uint256 wstETHBalanceBeforeRewards = wstETH.balanceOf(address(this));

        // Set high gas fees
        vm.fee(8000 gwei);
        vm.txGasPrice(9000 gwei);

        // Get the proper liquidation price for the tick
        uint128 price = protocol.getEffectivePriceForTick(posId.tick);
        int256 collateralLiquidated = protocol.i_tickValue(
            posId.tick,
            price,
            protocol.getLongTradingExpo(price),
            protocol.getLiqMultiplierAccumulator(),
            protocol.getTickData(posId.tick)
        );
        int256 vaultAssetAvailable = protocol.i_vaultAssetAvailable(price);
        uint256 expectedRewards = uint256(vaultAssetAvailable + collateralLiquidated);

        _waitBeforeLiquidation();
        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedRewards);
        LiqTickInfo[] memory liquidatedTicks = protocol.mockLiquidate(abi.encode(price), 1);

        // Check that the right number of positions have been liquidated
        assertEq(liquidatedTicks.length, 1, "One position should have been liquidated");

        assertEq(
            wstETH.balanceOf(address(this)) - wstETHBalanceBeforeRewards,
            expectedRewards,
            "The liquidator did not receive the right amount of rewards"
        );
        assertEq(protocol.getBalanceVault(), 0, "The vault should have given what was left");
    }

    /**
     * @custom:scenario The user sends too much ether when liquidating positions
     * @custom:given The user performs a liquidation
     * @custom:when The user sends 0.5 ether as value in the `liquidate` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_liquidateEtherRefund() public {
        uint256 initialTotalPos = protocol.getTotalLongPositions();
        uint128 currentPrice = 2000 ether;
        bytes memory priceData = abi.encode(currentPrice);

        wstETH.mintAndApprove(address(this), 1_000_000 ether, address(protocol), type(uint256).max);

        // create high risk position
        protocol.initiateOpenPosition{
            value: oracleMiddleware.validationCost(priceData, ProtocolAction.InitiateOpenPosition)
        }(
            5 ether,
            9 * currentPrice / 10,
            type(uint128).max,
            protocol.getMaxLeverage(),
            address(this),
            payable(address(this)),
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost(priceData, ProtocolAction.ValidateOpenPosition)
        }(payable(address(this)), priceData, EMPTY_PREVIOUS_DATA);
        assertEq(protocol.getTotalLongPositions(), initialTotalPos + 1, "total positions after create");

        // price drops
        skip(1 hours);
        priceData = abi.encode(1000 ether);

        // disable rewards
        vm.prank(DEPLOYER);
        liquidationRewardsManager.setRewardsParameters(0, 0, 0, 0, 0, 0, 0, 0, 0.1 ether);

        // liquidate
        uint256 balanceBefore = address(this).balance;
        uint256 validationCost = oracleMiddleware.validationCost(priceData, ProtocolAction.Liquidation);
        // we use `liquidate` instead of `testLiquidate` to avoid testing the "hack" in the handler
        protocol.liquidate{ value: 0.5 ether }(priceData, 1);
        assertEq(protocol.getTotalLongPositions(), initialTotalPos, "total positions after liquidate");
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    /**
     * @custom:scenario The user liquidates with a reentrancy attempt
     * @custom:given A user being a smart contract that calls liquidate with too much ether
     * @custom:and A receive() function that calls liquidate again
     * @custom:when The user calls liquidate again from the callback
     * @custom:then The call reverts with InitializableReentrancyGuardReentrantCall
     */
    function test_RevertWhen_liquidateCalledWithReentrancy() public {
        uint128 price = 2000 ether;
        bytes memory priceData = abi.encode(price);
        if (_reenter) {
            vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardReentrantCall.selector);
            protocol.liquidate(priceData, 1);
            return;
        }

        setUpUserPositionInLong(
            OpenParams({
                user: USER_1,
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 5 ether,
                desiredLiqPrice: 1700 ether,
                price: price
            })
        );

        _reenter = true;
        // If a reentrancy occurred, the function should have been called 2 times
        vm.expectCall(address(protocol), abi.encodeWithSelector(protocol.liquidate.selector), 2);
        // The value sent will cause a refund, which will trigger the receive() function of this contract
        protocol.liquidate{ value: 1 }(priceData, 1);
    }

    // test refunds
    receive() external payable {
        // test reentrancy
        if (_reenter) {
            test_RevertWhen_liquidateCalledWithReentrancy();
            _reenter = false;
        }
    }
}
