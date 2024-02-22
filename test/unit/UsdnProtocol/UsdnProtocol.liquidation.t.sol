// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { USER_1, USER_2, DEPLOYER } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ILiquidationRewardsManagerErrorsEventsTypes } from
    "src/interfaces/OracleMiddleware/ILiquidationRewardsManagerErrorsEventsTypes.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { TickMath } from "src/libraries/TickMath.sol";

/// @custom:feature The `liquidate()` function of `UsdnProtocolActions`
contract TestUsdnProtocolLiquidation is UsdnProtocolBaseFixture {
    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        wstETH.mintAndApprove(address(this), 100_000 ether, address(protocol), type(uint256).max);
        wstETH.mintAndApprove(USER_1, 100_000 ether, address(protocol), type(uint256).max);

        usdn.approve(address(protocol), type(uint256).max);

        chainlinkGasPriceFeed.setLatestRoundData(1, 30 gwei, block.timestamp, 1);
        vm.txGasPrice(30 gwei);
    }

    /**
     * TODO To move to fixtures setup?
     * @notice Create user positions on the vault side (deposit and withdrawal)
     * @dev The order in which the actions are performed are defined as followed:
     * @dev InitiateDeposit -> ValidateDeposit -> InitiateWithdrawal
     * @param user User that performs the actions
     * @param untilAction Action after which the function returns
     * @param positionSize Amount of wstEth to deposit
     * @param price Current price
     */
    function setUpUserPositionInVault(address user, ProtocolAction untilAction, uint128 positionSize, uint256 price)
        public
    {
        bytes memory priceData = abi.encode(price);

        vm.prank(user);
        protocol.initiateDeposit(positionSize, priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        if (untilAction == ProtocolAction.InitiateDeposit) return;

        vm.prank(user);
        protocol.validateDeposit(priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        if (untilAction == ProtocolAction.ValidateDeposit) return;

        vm.prank(user);
        protocol.initiateWithdrawal(uint128(usdn.balanceOf(user)), priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        if (untilAction == ProtocolAction.InitiateWithdrawal) return;
    }

    /**
     * TODO To move to fixtures setup?
     * @notice Create user positions on the long side (open and close a position)
     * @dev The order in which the actions are performed are defined as followed:
     * @dev InitiateOpenPosition -> ValidateOpenPosition -> InitiateClosePosition
     * @param user User that performs the actions
     * @param untilAction Action after which the function returns
     * @param positionSize Amount of wstEth to deposit
     * @param desiredLiqPrice Price at which the position should be liquidated
     * @param price Current price
     * @return tick_ The tick at which the position was opened
     * @return tickVersion_ The tick version of the price tick
     * @return index_ The index of the new position inside the tick array
     */
    function setUpUserPositionInLong(
        address user,
        ProtocolAction untilAction,
        uint96 positionSize,
        uint128 desiredLiqPrice,
        uint256 price
    ) public returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        bytes memory priceData = abi.encode(price);

        vm.prank(user);
        (tick_, tickVersion_, index_) = protocol.initiateOpenPosition(positionSize, desiredLiqPrice, priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        if (untilAction == ProtocolAction.InitiateOpenPosition) return (tick_, tickVersion_, index_);

        vm.prank(user);
        protocol.validateOpenPosition(priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        if (untilAction == ProtocolAction.ValidateOpenPosition) return (tick_, tickVersion_, index_);

        vm.prank(user);
        protocol.initiateClosePosition(tick_, tickVersion_, index_, priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        if (untilAction == ProtocolAction.InitiateClosePosition) return (tick_, tickVersion_, index_);
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
        (int24 tick, uint256 tickVersion,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // TODO remove when the MockOracleMiddleware is fixed
        skip(31 minutes);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tick, tickVersion, 0, 0, 0);
        protocol.initiateDeposit(1 ether, abi.encode(effectivePriceForTick), "");
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
        (int24 tick, uint256 tickVersion,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // Initates the deposit for the other user
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateDeposit, 1 ether, price);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tick, tickVersion, 0, 0, 0);

        protocol.validateDeposit(abi.encode(effectivePriceForTick), "");
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
        (int24 tick, uint256 tickVersion,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // Initate and validate the deposit for the other user
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, 1 ether, price);

        // TODO remove when the MockOracleMiddleware is fixed
        skip(31 minutes);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tick, tickVersion, 0, 0, 0);

        protocol.initiateWithdrawal(uint128(usdn.balanceOf(address(this))), abi.encode(effectivePriceForTick), "");
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
        (int24 tick, uint256 tickVersion,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // Initate and validate the deposit, then initiate the withdrawal for the other user
        setUpUserPositionInVault(address(this), ProtocolAction.InitiateWithdrawal, 1 ether, price);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tick, tickVersion, 0, 0, 0);

        protocol.validateWithdrawal(abi.encode(effectivePriceForTick), "");
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
        (int24 tick, uint256 tickVersion,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // TODO remove when the MockOracleMiddleware is fixed
        skip(31 minutes);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tick, tickVersion, 0, 0, 0);
        protocol.initiateOpenPosition(1 ether, desiredLiqPrice - 200 ether, abi.encode(effectivePriceForTick), "");
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
        (int24 tick, uint256 tickVersion,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // Initates the position for the other user
        price -= 200 ether;
        desiredLiqPrice -= 200 ether;
        setUpUserPositionInLong(address(this), ProtocolAction.InitiateOpenPosition, 1 ether, desiredLiqPrice, price);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tick);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tick, tickVersion, 0, 0, 0);
        protocol.validateOpenPosition(abi.encode(effectivePriceForTick), "");
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
        (int24 tickToLiquidate, uint256 tickVersionToLiquidate,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // Initates and validates the position for the other user
        desiredLiqPrice -= 200 ether;
        (int24 tickToClose, uint256 tickVersionToClose, uint256 indexToClose) =
            setUpUserPositionInLong(address(this), ProtocolAction.ValidateOpenPosition, 1 ether, desiredLiqPrice, price);

        // TODO remove when the MockOracleMiddleware is fixed
        skip(31 minutes);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tickToLiquidate);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tickToLiquidate, tickVersionToLiquidate, 0, 0, 0);

        protocol.initiateClosePosition(
            tickToClose, tickVersionToClose, indexToClose, abi.encode(effectivePriceForTick), ""
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
        (int24 tickToLiquidate, uint256 tickVersionToLiquidate,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, desiredLiqPrice, price);

        // Initates and validates the position for the other user
        desiredLiqPrice -= 200 ether;
        setUpUserPositionInLong(address(this), ProtocolAction.InitiateClosePosition, 1 ether, desiredLiqPrice, price);

        // TODO remove when the MockOracleMiddleware is fixed
        skip(31 minutes);

        // When funding is positive, calculations will increase the liquidation price so this is enough
        uint256 effectivePriceForTick = protocol.getEffectivePriceForTick(tickToLiquidate);

        // Check that tick has been liquidated
        vm.expectEmit(true, true, false, false);
        emit IUsdnProtocolEvents.LiquidatedTick(tickToLiquidate, tickVersionToLiquidate, 0, 0, 0);

        protocol.validateClosePosition(abi.encode(effectivePriceForTick), "");
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

        vm.startPrank(users[0]);
        protocol.initiateOpenPosition(5 ether, 1700 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        vm.stopPrank();

        priceData = abi.encode(1950 ether);

        uint256 wstETHBalanceBeforeRewards = wstETH.balanceOf(address(this));
        uint256 vaultBalanceBeforeRewards = protocol.balanceVault();
        uint256 longPositionsBeforeLiquidation = protocol.totalLongPositions();

        protocol.liquidate(priceData, 1);

        // check that the liquidator didn't receive any rewards
        assertEq(
            wstETHBalanceBeforeRewards,
            wstETH.balanceOf(address(this)),
            "The liquidator should not receive rewards if there were no liquidations"
        );

        // check that the vault balance did not change
        assertEq(
            vaultBalanceBeforeRewards,
            protocol.balanceVault(),
            "The vault balance should not change if there were no liquidations"
        );

        // check if first total long positions match initial value
        assertEq(
            longPositionsBeforeLiquidation,
            protocol.totalLongPositions(),
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
        (int24 tick,,) =
            setUpUserPositionInLong(USER_1, ProtocolAction.ValidateOpenPosition, 5 ether, 1700 ether, price);

        // Change The rewards calculations parameters to not be dependent of the initial values
        vm.prank(DEPLOYER);
        liquidationRewardsManager.setRewardsParameters(10_000, 30_000, 1000 gwei, 20_000);

        // Trigger PnL and funding calculations now to avoid having to predict them later
        protocol.i_applyPnlAndFunding(price, uint128(block.timestamp));

        uint256 expectedLiquidatorRewards = liquidationRewardsManager.getLiquidationRewards(1, 0);
        // Sanity check
        assertGt(expectedLiquidatorRewards, 0, "The expected liquidation rewards should be greater than 0");

        uint256 wstETHBalanceBeforeRewards = wstETH.balanceOf(address(this));
        uint256 vaultBalanceBeforeRewards = protocol.balanceVault();

        // Get the proper liquidation price for the tick
        price = protocol.getEffectivePriceForTick(tick);
        int256 collateralLiquidated = protocol.i_tickValue(price, tick, protocol.totalExpoByTick(tick));

        vm.expectEmit();
        emit IUsdnProtocolEvents.LiquidatorRewarded(address(this), expectedLiquidatorRewards);
        protocol.liquidate(abi.encode(price), 1);

        // Check that the liquidator received its rewards
        assertEq(
            wstETH.balanceOf(address(this)) - wstETHBalanceBeforeRewards,
            expectedLiquidatorRewards,
            "The liquidator did not receive the right amount of rewards"
        );

        // check that the vault balance got updated
        assertEq(
            vaultBalanceBeforeRewards + uint256(collateralLiquidated) - protocol.balanceVault(),
            expectedLiquidatorRewards,
            "The vault does not contain the right amount of funds"
        );
    }

    /**
     * @custom:scenario The gas usage of UsdnProtocolActions.liquidate(bytes,uint16) matches the values set in
     * LiquidationRewardsManager.getRewardsParameters
     * @custom:given There are one or more ticks that can be liquidated
     * @custom:when A liquidator calls the function liquidate
     * @custom:then The gas usage matches the LiquidationRewardsManager parameters
     */
    function test_gasUsageOfLiquidateFunction() public {
        bytes memory priceData = abi.encode(4500 ether);

        vm.startPrank(users[0]);
        protocol.initiateOpenPosition(1 ether, 4000 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        protocol.initiateOpenPosition(1 ether, 3950 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        protocol.initiateOpenPosition(1 ether, 3900 ether, priceData, "");
        protocol.validateOpenPosition(priceData, "");
        vm.stopPrank();

        ILiquidationRewardsManagerErrorsEventsTypes.RewardsParameters memory rewardsParameters =
            liquidationRewardsManager.getRewardsParameters();

        uint256 snapshotId = vm.snapshot();

        uint256[] memory gasUsedArray = new uint256[](3);
        for (uint16 ticksToLiquidate = 1; ticksToLiquidate <= 3; ++ticksToLiquidate) {
            // Get a price that liquidates `ticksToLiquidate` ticks
            priceData = abi.encode(4010 ether - (50 ether * ticksToLiquidate));

            uint256 startGas = gasleft();
            uint256 positionsLiquidated = protocol.liquidate(priceData, ticksToLiquidate);
            uint256 gasUsed = startGas - gasleft();
            gasUsedArray[ticksToLiquidate - 1] = gasUsed;

            // Make sure the expected amount of computation was executed
            assertEq(
                positionsLiquidated,
                ticksToLiquidate,
                "We expect 1, 2 or 3 positions liquidated depending on the iteration"
            );

            vm.revertTo(snapshotId);
        }

        // Calculate the average gas used exclusively by a loop of tick liquidation
        uint256 averageGasUsedPerTick = (gasUsedArray[1] - gasUsedArray[0] + gasUsedArray[2] - gasUsedArray[1]) / 2;
        // Calculate the average gas used by everything BUT loops of tick liquidation
        uint256 averageOtherGasUsed = (
            gasUsedArray[0] - averageGasUsedPerTick + gasUsedArray[1] - (averageGasUsedPerTick * 2) + gasUsedArray[2]
                - (averageGasUsedPerTick * 3)
        ) / 3;

        // Check that the gas usage per tick matches the gasUsedPerTick parameter in the LiquidationRewardsManager
        assertEq(
            averageGasUsedPerTick,
            rewardsParameters.gasUsedPerTick,
            "The result should match the gasUsedPerTick parameter set in LiquidationRewardsManager's constructor"
        );
        // Check that the other gas usage matches the otherGasUsed parameter in the LiquidationRewardsManager
        assertEq(
            averageOtherGasUsed,
            rewardsParameters.otherGasUsed,
            "The result should match the otherGasUsed parameter set in LiquidationRewardsManager's constructor"
        );
    }

    /**
     * @custom:scenario The user sends too much ether when liquidating positions
     * @custom:given The user performs a liquidation
     * @custom:when The user sends 0.5 ether as value in the `liquidate` call
     * @custom:then The user gets refunded the excess ether (0.5 ether - validationCost)
     */
    function test_liquidateEtherRefund() public {
        uint256 initialTotalPos = protocol.totalLongPositions();
        uint128 currentPrice = 2000 ether;
        bytes memory priceData = abi.encode(currentPrice);

        wstETH.mint(address(this), 1_000_000 ether);
        wstETH.approve(address(protocol), type(uint256).max);

        // create high risk position
        protocol.initiateOpenPosition{
            value: oracleMiddleware.validationCost(priceData, ProtocolAction.InitiateOpenPosition)
        }(5 ether, 9 * currentPrice / 10, priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
        protocol.validateOpenPosition{
            value: oracleMiddleware.validationCost(priceData, ProtocolAction.ValidateOpenPosition)
        }(priceData, "");
        assertEq(protocol.totalLongPositions(), initialTotalPos + 1, "total positions after create");

        // liquidate
        currentPrice = 1750 ether;
        priceData = abi.encode(currentPrice);

        uint256 balanceBefore = address(this).balance;
        uint256 validationCost = oracleMiddleware.validationCost(priceData, ProtocolAction.Liquidation);
        protocol.liquidate{ value: 0.5 ether }(priceData, 1);
        assertEq(protocol.totalLongPositions(), initialTotalPos, "total positions after liquidate");
        assertEq(address(this).balance, balanceBefore - validationCost, "user balance after refund");
    }

    // test refunds
    receive() external payable { }
}
