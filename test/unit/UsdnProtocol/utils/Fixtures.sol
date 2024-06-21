// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { ADMIN, DEPLOYER } from "../../../utils/Constants.sol";
import { BaseFixture } from "../../../utils/Fixtures.sol";
import { IEventsErrors } from "../../../utils/IEventsErrors.sol";
import { Sdex } from "../../../utils/Sdex.sol";
import { WstETH } from "../../../utils/WstEth.sol";
import { MockChainlinkOnChain } from "../../Middlewares/utils/MockChainlinkOnChain.sol";
import { RebalancerHandler } from "../../Rebalancer/utils/Handler.sol";
import { UsdnProtocolHandler } from "./Handler.sol";
import { MockOracleMiddleware } from "./MockOracleMiddleware.sol";

import { LiquidationRewardsManager } from "../../../../src/OracleMiddleware/LiquidationRewardsManager.sol";
import { Usdn } from "../../../../src/Usdn/Usdn.sol";
import { IUsdnProtocolErrors } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import { IUsdnProtocolEvents } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolTypes } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { HugeUint } from "../../../../src/libraries/HugeUint.sol";
import { Permit2TokenBitfield } from "../../../../src/libraries/Permit2TokenBitfield.sol";

/**
 * @title UsdnProtocolBaseFixture
 * @dev Utils for testing the USDN Protocol
 */
contract UsdnProtocolBaseFixture is BaseFixture, IUsdnProtocolErrors, IEventsErrors, IUsdnProtocolEvents {
    struct Flags {
        bool enablePositionFees;
        bool enableProtocolFees;
        bool enableFunding;
        bool enableLimits;
        bool enableUsdnRebase;
        bool enableSecurityDeposit;
        bool enableSdexBurnOnDeposit;
        bool enableLongLimit;
        bool enableRebalancer;
    }

    struct SetUpParams {
        uint128 initialDeposit;
        uint128 initialLong;
        uint128 initialPrice;
        uint256 initialTimestamp;
        uint256 initialBlock;
        Flags flags;
    }

    Permit2TokenBitfield.Bitfield constant NO_PERMIT2 = Permit2TokenBitfield.Bitfield.wrap(0);

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
            enableLongLimit: false,
            enableRebalancer: false
        })
    });

    struct OpenParams {
        address user;
        IUsdnProtocolTypes.ProtocolAction untilAction;
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
    RebalancerHandler public rebalancer;
    UsdnProtocolHandler public protocol;
    IUsdnProtocolTypes.PositionId public initialPosition;
    uint256 public usdnInitialTotalSupply;
    address[] public users;

    int24 internal _tickSpacing = 100; // tick spacing 100 = 1%
    IUsdnProtocolTypes.PreviousActionsData internal EMPTY_PREVIOUS_DATA =
        IUsdnProtocolTypes.PreviousActionsData({ priceData: new bytes[](0), rawIndices: new uint128[](0) });

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
            _tickSpacing,
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
            protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0);
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

        rebalancer = new RebalancerHandler(protocol);
        if (testParams.flags.enableRebalancer) {
            protocol.setRebalancer(rebalancer);
        }

        // leverage approx 2x
        protocol.initialize(
            testParams.initialDeposit,
            testParams.initialLong,
            testParams.initialPrice / 2,
            abi.encode(testParams.initialPrice)
        );

        initialPosition.tick = protocol.getHighestPopulatedTick();

        // separate the roles ADMIN and DEPLOYER
        protocol.transferOwnership(ADMIN);
        rebalancer.transferOwnership(ADMIN);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        protocol.acceptOwnership();
        rebalancer.acceptOwnership();
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
        (IUsdnProtocolTypes.Position memory firstPos,) =
            protocol.getLongPosition(IUsdnProtocolTypes.PositionId(firstPosTick, 0, 0));

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
    function setUpUserPositionInVault(
        address user,
        IUsdnProtocolTypes.ProtocolAction untilAction,
        uint128 positionSize,
        uint256 price
    ) public prankUser(user) {
        sdex.mintAndApprove(
            user,
            usdn.convertToTokens(
                protocol.i_calcMintUsdnShares(
                    positionSize, uint256(protocol.i_vaultAssetAvailable(uint128(price))), usdn.totalShares(), price
                )
            ) * protocol.getSdexBurnOnDepositRatio() / protocol.SDEX_BURN_ON_DEPOSIT_DIVISOR(),
            address(protocol),
            type(uint256).max
        );

        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(user, positionSize, address(protocol), positionSize);
        bytes memory priceData = abi.encode(price);

        protocol.initiateDeposit{ value: securityDepositValue }(
            positionSize, user, payable(user), NO_PERMIT2, priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        if (untilAction == IUsdnProtocolTypes.ProtocolAction.InitiateDeposit) return;

        protocol.validateDeposit(payable(user), priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == IUsdnProtocolTypes.ProtocolAction.ValidateDeposit) return;

        uint256 sharesOf = usdn.sharesOf(user);
        usdn.approve(address(protocol), usdn.convertToTokensRoundUp(sharesOf));
        protocol.initiateWithdrawal{ value: securityDepositValue }(
            uint152(sharesOf), user, payable(user), priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();

        if (untilAction == IUsdnProtocolTypes.ProtocolAction.InitiateWithdrawal) return;

        protocol.validateWithdrawal(payable(user), priceData, EMPTY_PREVIOUS_DATA);
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
        returns (IUsdnProtocolTypes.PositionId memory posId_)
    {
        uint256 securityDepositValue = protocol.getSecurityDepositValue();
        wstETH.mintAndApprove(openParams.user, openParams.positionSize, address(protocol), openParams.positionSize);
        bytes memory priceData = abi.encode(openParams.price);

        bool success;
        (success, posId_) = protocol.initiateOpenPosition{ value: securityDepositValue }(
            openParams.positionSize,
            openParams.desiredLiqPrice,
            openParams.user,
            payable(openParams.user),
            NO_PERMIT2,
            priceData,
            EMPTY_PREVIOUS_DATA
        );
        assertTrue(success, "initiate open position success");
        _waitDelay();
        if (openParams.untilAction == IUsdnProtocolTypes.ProtocolAction.InitiateOpenPosition) return (posId_);

        protocol.validateOpenPosition(payable(openParams.user), priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (openParams.untilAction == IUsdnProtocolTypes.ProtocolAction.ValidateOpenPosition) return (posId_);

        protocol.initiateClosePosition{ value: securityDepositValue }(
            posId_, openParams.positionSize, openParams.user, payable(openParams.user), priceData, EMPTY_PREVIOUS_DATA
        );
        _waitDelay();
        if (openParams.untilAction == IUsdnProtocolTypes.ProtocolAction.InitiateClosePosition) return (posId_);

        protocol.validateClosePosition(payable(openParams.user), priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
    }

    /**
     * @dev Helper function to initiate a new position and liquidate it before it gets validated
     * @return posId_ The unique position identifier
     */
    function _createStalePendingActionHelper() internal returns (IUsdnProtocolTypes.PositionId memory posId_) {
        // create a pending action with a liquidation price around $1700
        posId_ = setUpUserPositionInLong(
            OpenParams(
                address(this), IUsdnProtocolTypes.ProtocolAction.InitiateOpenPosition, 1 ether, 1700 ether, 2000 ether
            )
        );

        // the price drops to $1500 and the position gets liquidated
        _waitBeforeLiquidation();
        protocol.liquidate(abi.encode(uint128(1500 ether)), 10);

        // the pending action is stale
        uint256 currentTickVersion = protocol.getTickVersion(posId_.tick);
        IUsdnProtocolTypes.PendingAction memory action = protocol.getUserPendingAction(address(this));
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
    function _assertActionsEqual(
        IUsdnProtocolTypes.PendingAction memory a,
        IUsdnProtocolTypes.PendingAction memory b,
        string memory err
    ) internal {
        assertTrue(a.action == b.action, string.concat(err, " - action type"));
        assertEq(a.timestamp, b.timestamp, string.concat(err, " - action timestamp"));
        assertEq(a.to, b.to, string.concat(err, " - action to"));
        assertEq(a.validator, b.validator, string.concat(err, " - action validator"));
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

    function _waitBeforeActionablePendingAction() internal {
        skip(protocol.getValidationDeadline() + 1);
    }

    /// @dev Calculate proper initial values from randoms to initialize a balanced protocol
    function _randInitBalanced(uint128 initialAmount) internal {
        // deploy protocol temporarily to get access to constants and calculations
        // it will be re-deployed at the end of the function with new initial values
        params = DEFAULT_PARAMS;
        params.flags.enableLimits = true;
        _setUp(params);

        // cannot be less than 1 ether
        initialAmount = uint128(bound(initialAmount, protocol.MIN_INIT_DEPOSIT(), 5000 ether));

        int256 depositLimit = protocol.getDepositExpoImbalanceLimitBps();
        uint128 margin = uint128(initialAmount * uint256(depositLimit) / protocol.BPS_DIVISOR());

        uint128 initialDeposit = uint128(bound(initialAmount, initialAmount, initialAmount + margin));

        int256 longLimit = protocol.getOpenExpoImbalanceLimitBps();
        margin = uint128(initialAmount * uint256(longLimit) / protocol.BPS_DIVISOR());

        uint256 initialLongExpo = bound(initialAmount, initialAmount, initialAmount + margin);

        uint128 liquidationPriceWithoutPenalty = protocol.getEffectivePriceForTick(
            protocol.getEffectiveTickForPrice(
                params.initialPrice / 2, 0, 0, HugeUint.wrap(0), protocol.getTickSpacing()
            ),
            0,
            0,
            HugeUint.wrap(0)
        );

        // long amount
        uint128 initialLong = uint128(
            initialLongExpo * (params.initialPrice - liquidationPriceWithoutPenalty) / liquidationPriceWithoutPenalty
        );

        // assign initial values
        params.initialDeposit = initialDeposit;
        params.initialLong = initialLong;

        // init protocol
        _setUp(params);
    }

    /// @dev Wait for the required delay to allow mock middleware price update
    function _waitMockMiddlewarePriceDelay() internal {
        skip(30 minutes - oracleMiddleware.getValidationDelay());
    }
}
