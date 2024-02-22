// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { MockChainlinkOnChain } from "test/unit/OracleMiddleware/utils/MockChainlinkOnChain.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { Position, PendingAction, ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Usdn } from "src/Usdn.sol";

/**
 * @title UsdnProtocolBaseFixture
 * @dev Utils for testing the USDN Protocol
 */
contract UsdnProtocolBaseFixture is BaseFixture, IUsdnProtocolErrors, IUsdnProtocolEvents {
    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialPrice;
        uint256 initialTimestamp;
        uint256 initialBlock;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 10 ether,
        initialLong: 5 ether,
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC,
        initialBlock: block.number
    });

    Usdn public usdn;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    MockChainlinkOnChain public chainlinkGasPriceFeed;
    LiquidationRewardsManager public liquidationRewardsManager;
    UsdnProtocolHandler public protocol;
    uint256 public usdnInitialTotalSupply;
    uint128 public defaultPosLeverage;
    uint128 public initialLongLeverage;
    address[] public users;

    function _setUp(SetUpParams memory testParams) public virtual {
        vm.warp(testParams.initialTimestamp);
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        oracleMiddleware = new MockOracleMiddleware();
        chainlinkGasPriceFeed = new MockChainlinkOnChain();
        liquidationRewardsManager =
            new LiquidationRewardsManager(address(chainlinkGasPriceFeed), IWstETH(address(wstETH)), 2 days);

        protocol = new UsdnProtocolHandler(
            usdn,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN // Fee collector
        );
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        wstETH.approve(address(protocol), type(uint256).max);
        // leverage approx 2x
        protocol.initialize(
            testParams.initialDeposit,
            testParams.initialLong,
            testParams.initialPrice / 2,
            abi.encode(testParams.initialPrice)
        );
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0, 0);
        Position memory firstPos =
            protocol.getLongPosition(protocol.getEffectiveTickForPrice(testParams.initialPrice / 2), 0, 0);
        // separate the roles ADMIN and DEPLOYER
        protocol.transferOwnership(ADMIN);
        vm.stopPrank();

        usdnInitialTotalSupply = usdn.totalSupply();
        defaultPosLeverage = defaultPos.leverage;
        initialLongLeverage = firstPos.leverage;
        params = testParams;
        // initialize x10 EOA addresses with 10K ETH and ~8.5K WSTETH
        createAndFundUsers(10, 10_000 ether);
    }

    function test_setUp() public {
        _setUp(DEFAULT_PARAMS);
        assertGt(protocol.tickSpacing(), 1, "tickSpacing"); // we want to test all functions for a tickSpacing > 1
        assertEq(
            wstETH.balanceOf(address(protocol)), params.initialDeposit + params.initialLong, "wstETH protocol balance"
        );
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "usdn dead address balance");
        uint256 usdnTotalSupply = uint256(params.initialDeposit) * params.initialPrice / 10 ** 18;
        assertEq(usdnTotalSupply, usdnInitialTotalSupply, "usdn total supply");
        assertEq(usdn.balanceOf(DEPLOYER), usdnTotalSupply - protocol.MIN_USDN_SUPPLY(), "usdn deployer balance");
        Position memory defaultPos = protocol.getLongPosition(protocol.minTick(), 0, 0);
        assertEq(defaultPos.leverage, 1_000_000_000_000_000_005_039, "default pos leverage");
        assertEq(defaultPos.timestamp, block.timestamp, "default pos timestamp");
        assertEq(defaultPos.user, protocol.DEAD_ADDRESS(), "default pos user");
        assertEq(defaultPos.amount, protocol.FIRST_LONG_AMOUNT(), "default pos amount");
        Position memory firstPos =
            protocol.getLongPosition(protocol.getEffectiveTickForPrice(params.initialPrice / 2), 0, 0);
        assertEq(firstPos.leverage, 1_983_994_053_940_692_631_258, "first pos leverage");
        assertEq(firstPos.timestamp, block.timestamp, "first pos timestamp");
        assertEq(firstPos.user, DEPLOYER, "first pos user");
        assertEq(firstPos.amount, params.initialLong - protocol.FIRST_LONG_AMOUNT(), "first pos amount");
        assertEq(protocol.pendingProtocolFee(), 0, "initial pending protocol fee");
        assertEq(protocol.feeCollector(), ADMIN, "fee collector");
        assertEq(protocol.owner(), ADMIN, "protocol owner");
    }

    /**
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

        vm.prank(user);
        protocol.validateWithdrawal(priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);
    }

    /**
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

        vm.prank(user);
        protocol.validateClosePosition(priceData, "");
        skip(oracleMiddleware.validationDelay() + 1);

        return (tick_, tickVersion_, index_);
    }

    // create userCount funded addresses with ETH and underlying
    function createAndFundUsers(uint256 userCount, uint256 initialBalance) public {
        for (uint256 i; i < userCount; i++) {
            address user = vm.addr(i + 1);
            vm.deal(user, initialBalance * 2);
            vm.startPrank(user);
            (bool success,) = address(wstETH).call{ value: initialBalance }("");
            require(success, "swap asset error");
            wstETH.approve(address(protocol), type(uint256).max);
            assertTrue(wstETH.balanceOf(user) != 0, "user with empty wallet");
            vm.stopPrank();

            users.push(user);
        }
    }

    /**
     * @dev Helper function to assert two `PendingAction` are equal.
     * Reverts if not equal.
     * @param a First `PendingAction`
     * @param b Second `PendingAction`
     */
    function _assertActionsEqual(PendingAction memory a, PendingAction memory b, string memory err) internal {
        assertTrue(a.action == b.action, string.concat(err, " - action type"));
        assertEq(a.timestamp, b.timestamp, string.concat(err, " - action timestamp"));
        assertEq(a.user, b.user, string.concat(err, " - action user"));
        assertEq(a.var1, b.var1, string.concat(err, " - action var1"));
        assertEq(a.amount, b.amount, string.concat(err, " - action amount"));
        assertEq(a.var2, b.var2, string.concat(err, " - action var2"));
        assertEq(a.var3, b.var3, string.concat(err, " - action var3"));
        assertEq(a.var4, b.var4, string.concat(err, " - action var4"));
        assertEq(a.var5, b.var5, string.concat(err, " - action var5"));
        assertEq(a.var6, b.var6, string.concat(err, " - action var6"));
    }
}
