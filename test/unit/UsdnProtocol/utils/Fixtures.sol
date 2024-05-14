// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { IEvents } from "test/utils/IEvents.sol";
import { Sdex } from "test/utils/Sdex.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import {
    Position,
    PendingAction,
    ProtocolAction,
    PreviousActionsData,
    PositionId
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { Usdn } from "src/Usdn/Usdn.sol";

/**
 * @title UsdnProtocolBaseFixture
 * @dev Utils for testing the USDN Protocol
 */
contract UsdnProtocolBaseFixture is BaseFixture, IUsdnProtocolErrors, IEvents, IUsdnProtocolEvents {
    struct Flags {
        bool enablePositionFees;
        bool enableProtocolFees;
        bool enableFunding;
        bool enableLimits;
        bool enableUsdnRebase;
        bool enableSecurityDeposit;
        bool enableSdexBurnOnDeposit;
        bool enableLongLimit;
    }

    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialPrice;
        uint256 initialTimestamp;
        uint256 initialBlock;
        Flags flags;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 4.919970269703463156 ether,
        initialLong: 5 ether,
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC,
        initialBlock: block.number,
        flags: Flags({
            enablePositionFees: false,
            enableProtocolFees: false,
            enableFunding: false,
            enableLimits: false,
            enableUsdnRebase: false,
            enableSecurityDeposit: false,
            enableSdexBurnOnDeposit: false,
            enableLongLimit: false
        })
    });

    struct OpenParams {
        address user;
        ProtocolAction untilAction;
        uint128 positionSize;
        uint128 desiredLiqPrice;
        uint256 price;
    }

    Usdn public usdn;
    Sdex public sdex;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    MockChainlinkOnChain public chainlinkGasPriceFeed;
    LiquidationRewardsManager public liquidationRewardsManager;
    UsdnProtocolHandler public protocol;
    uint256 public usdnInitialTotalSupply;
    address[] public users;

    PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

    modifier prankUser(address user) {
        vm.startPrank(user);
        _;
        vm.stopPrank();
    }

    function _setUp(SetUpParams memory testParams) public virtual {
        vm.warp(testParams.initialTimestamp);
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));
        wstETH = new WstETH();
        sdex = new Sdex();
        oracleMiddleware = new MockOracleMiddleware();
        chainlinkGasPriceFeed = new MockChainlinkOnChain();
        liquidationRewardsManager = new LiquidationRewardsManager(address(chainlinkGasPriceFeed), wstETH, 2 days);

        protocol = new UsdnProtocolHandler(
            usdn,
            sdex,
            wstETH,
            oracleMiddleware,
            liquidationRewardsManager,
            100, // tick spacing 100 = 1%
            ADMIN // Fee collector
        );
        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));

        if (!testParams.flags.enablePositionFees) {
            protocol.setPositionFeeBps(0);
            protocol.setVaultFeeBps(0);
        }
        if (!testParams.flags.enableProtocolFees) {
            protocol.setProtocolFeeBps(0);
        }
        if (!testParams.flags.enableFunding) {
            protocol.setFundingSF(0);
            protocol.resetEMA();
        }
        if (!params.flags.enableUsdnRebase) {
            // set a high target price to effectively disable rebases
            protocol.setUsdnRebaseThreshold(type(uint128).max);
            protocol.setTargetUsdnPrice(type(uint128).max);
        }
        if (!params.flags.enableSecurityDeposit) {
            protocol.setSecurityDepositValue(0);
        }

        // disable imbalance limits
        if (!testParams.flags.enableLimits) {
            protocol.setExpoImbalanceLimits(0, 0, 0, 0);
        }

        // disable burn sdex on deposit
        if (!testParams.flags.enableSdexBurnOnDeposit) {
            protocol.setSdexBurnOnDepositRatio(0);
        }

        // disable open position limit
        if (!testParams.flags.enableLongLimit) {
            protocol.setMinLongPosition(0);
        }

        wstETH.approve(address(protocol), type(uint256).max);

        // leverage approx 2x
        protocol.initialize(
            testParams.initialDeposit,
            testParams.initialLong,
            testParams.initialPrice / 2,
            abi.encode(testParams.initialPrice)
        );

        // separate the roles ADMIN and DEPLOYER
        protocol.transferOwnership(ADMIN);
        vm.stopPrank();

        usdnInitialTotalSupply = usdn.totalSupply();
        params = testParams;
    }

    function test_setUp() public {
        _setUp(DEFAULT_PARAMS);
        assertGt(protocol.getTickSpacing(), 1, "tickSpacing"); // we want to test all functions for a tickSpacing > 1
        assertEq(
            wstETH.balanceOf(address(protocol)), params.initialDeposit + params.initialLong, "wstETH protocol balance"
        );
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "usdn dead address balance");
        uint256 usdnTotalSupply = uint256(params.initialDeposit) * params.initialPrice / 10 ** 18;
        usdnTotalSupply -= usdnTotalSupply * protocol.getPositionFeeBps() / protocol.BPS_DIVISOR();
        assertEq(usdnTotalSupply, usdnInitialTotalSupply, "usdn total supply");
        assertEq(usdn.balanceOf(DEPLOYER), usdnTotalSupply - protocol.MIN_USDN_SUPPLY(), "usdn deployer balance");
        int24 firstPosTick = protocol.getHighestPopulatedTick();
        (Position memory firstPos,) = protocol.getLongPosition(PositionId(firstPosTick, 0, 0));

        assertEq(firstPos.totalExpo, 9_919_970_269_703_463_156, "first position total expo");
        assertEq(firstPos.timestamp, block.timestamp, "first pos timestamp");
        assertEq(firstPos.user, DEPLOYER, "first pos user");
        assertEq(firstPos.amount, params.initialLong, "first pos amount");
        assertEq(protocol.getPendingProtocolFee(), 0, "initial pending protocol fee");
        assertEq(protocol.getFeeCollector(), ADMIN, "fee collector");
        assertEq(protocol.owner(), ADMIN, "protocol owner");
    }

    /**
     * @notice Create user positions on the vault side (deposit and withdrawal)
     * @dev The order in which the actions are performed are defined as followed:
     * @dev InitiateDeposit -> ValidateDeposit -> InitiateWithdrawal -> ValidateWithdrawal
     * @param user User that performs the actions
     * @param untilAction Action after which the function returns
     * @param positionSize Amount of wstEth to deposit
     * @param price Current price
     */
    function setUpUserPositionInVault(address user, ProtocolAction untilAction, uint128 positionSize, uint256 price)
        public
        prankUser(user)
    {
        sdex.mintAndApprove(
            user,
            protocol.i_calcMintUsdn(
                positionSize, uint256(protocol.i_vaultAssetAvailable(uint128(price))), usdn.totalSupply(), price
            ) * protocol.getSdexBurnOnDepositRatio() / protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR(),
            address(protocol),
            type(uint256).max
        );

        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(user, positionSize, address(protocol), positionSize);
        bytes memory priceData = abi.encode(price);

        protocol.initiateDeposit{ value: securityDepositValue }(positionSize, priceData, EMPTY_PREVIOUS_DATA, user);
        _waitDelay();
        if (untilAction == ProtocolAction.InitiateDeposit) return;

        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == ProtocolAction.ValidateDeposit) return;

        uint256 balanceOf = usdn.balanceOf(user);
        usdn.approve(address(protocol), balanceOf);
        protocol.initiateWithdrawal{ value: securityDepositValue }(
            uint128(balanceOf), priceData, EMPTY_PREVIOUS_DATA, user
        );
        _waitDelay();

        if (untilAction == ProtocolAction.InitiateWithdrawal) return;

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
    }

    /**
     * @notice Create user positions on the long side (open and close a position)
     * @dev The order in which the actions are performed are defined as followed:
     * @dev InitiateOpenPosition -> ValidateOpenPosition -> InitiateClosePosition -> ValidateWithdrawal
     * @param openParams open position params
     * @return posId_ The unique position identifier
     */
    function setUpUserPositionInLong(OpenParams memory openParams)
        public
        prankUser(openParams.user)
        returns (PositionId memory posId_)
    {
        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(openParams.user, openParams.positionSize, address(protocol), openParams.positionSize);
        bytes memory priceData = abi.encode(openParams.price);

        posId_ = protocol.initiateOpenPosition{ value: securityDepositValue }(
            openParams.positionSize, openParams.desiredLiqPrice, priceData, EMPTY_PREVIOUS_DATA, openParams.user
        );
        _waitDelay();
        if (openParams.untilAction == ProtocolAction.InitiateOpenPosition) return (posId_);

        protocol.validateOpenPosition(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (openParams.untilAction == ProtocolAction.ValidateOpenPosition) return (posId_);

        protocol.initiateClosePosition{ value: securityDepositValue }(
            posId_, openParams.positionSize, priceData, EMPTY_PREVIOUS_DATA, openParams.user
        );
        _waitDelay();
        if (openParams.untilAction == ProtocolAction.InitiateClosePosition) return (posId_);

        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
    }

    /**
     * @dev Helper function to initiate a new position and liquidate it before it gets validated
     * @return posId_ The unique position identifier
     */
    function _createStalePendingActionHelper() internal returns (PositionId memory posId_) {
        // create a pending action with a liquidation price around $1700
        posId_ = setUpUserPositionInLong(
            OpenParams(address(this), ProtocolAction.InitiateOpenPosition, 1 ether, 1700 ether, 2000 ether)
        );

        // the price drops to $1500 and the position gets liquidated
        _waitBeforeLiquidation();
        protocol.liquidate(abi.encode(uint128(1500 ether)), 10);

        // the pending action is stale
        uint256 currentTickVersion = protocol.getTickVersion(posId_.tick);
        PendingAction memory action = protocol.getUserPendingAction(address(this));
        assertEq(action.var3, posId_.tickVersion, "tick version");
        assertTrue(action.var3 != currentTickVersion, "current tick version");
    }

    /**
     * @dev Helper function to assert two `PendingAction` are equal.
     * Reverts if not equal.
     * @param a First `PendingAction`
     * @param b Second `PendingAction`
     * @param err Assert message prefix
     */
    function _assertActionsEqual(PendingAction memory a, PendingAction memory b, string memory err) internal {
        assertTrue(a.action == b.action, string.concat(err, " - action type"));
        assertEq(a.timestamp, b.timestamp, string.concat(err, " - action timestamp"));
        assertEq(a.user, b.user, string.concat(err, " - action user"));
        assertEq(a.securityDepositValue, b.securityDepositValue, string.concat(err, " - action security deposit"));
        assertEq(a.var1, b.var1, string.concat(err, " - action var1"));
        assertEq(a.var2, b.var2, string.concat(err, " - action var2"));
        assertEq(a.var3, b.var3, string.concat(err, " - action var3"));
        assertEq(a.var4, b.var4, string.concat(err, " - action var4"));
        assertEq(a.var5, b.var5, string.concat(err, " - action var5"));
        assertEq(a.var6, b.var6, string.concat(err, " - action var6"));
    }

    function _waitDelay() internal {
        skip(oracleMiddleware.getValidationDelay() + 1);
    }

    function _waitBeforeLiquidation() internal {
        skip(31);
    }

    /// @dev Calculate proper initial values from randoms to initiate a balanced protocol
    function _randInitBalanced(uint128 initialDeposit, uint128 initialLong) internal {
        // deploy protocol at equilibrium temporarily to get access to constants and calculations
        // it will be re-deployed at the end of the function with new initial values
        params = DEFAULT_PARAMS;
        params.flags.enableLimits = true;
        params.initialDeposit = 5 ether;
        params.initialLong = 5 ether;
        _setUp(params);

        // cannot be less than 1 ether
        initialDeposit = uint128(bound(initialDeposit, protocol.MIN_INIT_DEPOSIT(), 5000 ether));

        (int256 openLimit,,,) = protocol.getExpoImbalanceLimits();
        uint128 margin = uint128(initialDeposit * uint256(openLimit) / protocol.BPS_DIVISOR());

        // min long expo to initiate a balanced protocol
        uint256 minLongExpo = initialDeposit - margin;
        // max long expo to initiate a balanced protocol
        uint256 maxLongExpo = initialDeposit + margin;

        uint128 liquidationPriceWithoutPenalty =
            protocol.getEffectivePriceForTick(protocol.getEffectiveTickForPrice(params.initialPrice / 2));

        // min long amount
        uint128 minLongAmount = uint128(
            minLongExpo * (params.initialPrice - liquidationPriceWithoutPenalty) / liquidationPriceWithoutPenalty
        );
        // bound to the minimum value
        if (minLongAmount < protocol.MIN_INIT_DEPOSIT()) {
            minLongAmount = uint128(protocol.MIN_INIT_DEPOSIT());
        }
        // max long amount
        uint128 maxLongAmount = uint128(
            maxLongExpo * (params.initialPrice - liquidationPriceWithoutPenalty) / liquidationPriceWithoutPenalty
        );

        // assign initial long amount in range min max
        initialLong = uint128(bound(initialLong, minLongAmount, maxLongAmount));

        // assign initial values
        params.initialDeposit = initialDeposit;
        params.initialLong = initialLong;

        // init protocol
        _setUp(params);
    }
}
