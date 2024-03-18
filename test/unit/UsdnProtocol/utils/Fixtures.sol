// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";
import { BaseFixture } from "test/utils/Fixtures.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { WstETH } from "test/utils/WstEth.sol";

import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";
import { IWstETH } from "src/interfaces/IWstETH.sol";
import { IUsdnProtocolEvents } from "src/interfaces/UsdnProtocol/IUsdnProtocolEvents.sol";
import { IUsdnProtocolErrors } from "src/interfaces/UsdnProtocol/IUsdnProtocolErrors.sol";
import {
    Position,
    PendingAction,
    ProtocolAction,
    PreviousActionsData
} from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
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
        bool enablePositionFees;
        bool enableProtocolFees;
        bool enableFunding;
        bool enableLimits;
        bool enableUsdnRebase;
    }

    SetUpParams public params;
    SetUpParams public DEFAULT_PARAMS = SetUpParams({
        initialDeposit: 10 ether,
        initialLong: 5 ether,
        initialPrice: 2000 ether, // 2000 USD per wstETH
        initialTimestamp: 1_704_092_400, // 2024-01-01 07:00:00 UTC,
        initialBlock: block.number,
        enablePositionFees: false,
        enableProtocolFees: true,
        enableFunding: true,
        enableLimits: false,
        enableUsdnRebase: false
    });

    Usdn public usdn;
    WstETH public wstETH;
    MockOracleMiddleware public oracleMiddleware;
    MockChainlinkOnChain public chainlinkGasPriceFeed;
    LiquidationRewardsManager public liquidationRewardsManager;
    UsdnProtocolHandler public protocol;
    uint256 public usdnInitialTotalSupply;
    uint256 public constant LEVERAGE_DECIMALS = 21;
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
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));

        if (!testParams.enablePositionFees) {
            protocol.setPositionFeeBps(0);
        }
        if (!testParams.enableProtocolFees) {
            protocol.setProtocolFeeBps(0);
        }
        if (!testParams.enableFunding) {
            protocol.setFundingSF(0);
            protocol.resetEMA();
        }
        if (!params.enableUsdnRebase) {
            // set a high target price to effectively disable rebases
            protocol.setUsdnRebaseThreshold(uint128(1000 * 10 ** protocol.getPriceFeedDecimals()));
            protocol.setTargetUsdnPrice(uint128(1000 * 10 ** protocol.getPriceFeedDecimals()));
        }

        // disable imbalance limits
        if (!testParams.enableLimits) {
            protocol.setExpoImbalanceLimitsBps(0, 0, 0, 0);
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
        int24 firstPosTick = protocol.getEffectiveTickForPrice(params.initialPrice / 2);
        Position memory firstPos = protocol.getLongPosition(
            firstPosTick + int24(protocol.getLiquidationPenalty()) * protocol.getTickSpacing(), 0, 0
        );

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
        wstETH.mintAndApprove(user, positionSize, address(protocol), positionSize);
        bytes memory priceData = abi.encode(price);

        protocol.initiateDeposit(positionSize, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == ProtocolAction.InitiateDeposit) return;

        protocol.validateDeposit(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == ProtocolAction.ValidateDeposit) return;

        protocol.initiateWithdrawal(uint128(usdn.balanceOf(user)), priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == ProtocolAction.InitiateWithdrawal) return;

        protocol.validateWithdrawal(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
    }

    /**
     * @notice Create user positions on the long side (open and close a position)
     * @dev The order in which the actions are performed are defined as followed:
     * @dev InitiateOpenPosition -> ValidateOpenPosition -> InitiateClosePosition -> ValidateWithdrawal
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
        uint128 positionSize,
        uint128 desiredLiqPrice,
        uint256 price
    ) public prankUser(user) returns (int24 tick_, uint256 tickVersion_, uint256 index_) {
        wstETH.mintAndApprove(user, positionSize, address(protocol), positionSize);
        bytes memory priceData = abi.encode(price);

        (tick_, tickVersion_, index_) =
            protocol.initiateOpenPosition(positionSize, desiredLiqPrice, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == ProtocolAction.InitiateOpenPosition) return (tick_, tickVersion_, index_);

        protocol.validateOpenPosition(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == ProtocolAction.ValidateOpenPosition) return (tick_, tickVersion_, index_);

        protocol.initiateClosePosition(tick_, tickVersion_, index_, positionSize, priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();
        if (untilAction == ProtocolAction.InitiateClosePosition) return (tick_, tickVersion_, index_);

        protocol.validateClosePosition(priceData, EMPTY_PREVIOUS_DATA);
        _waitDelay();

        return (tick_, tickVersion_, index_);
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

    function _waitDelay() internal {
        skip(oracleMiddleware.getValidationDelay() + 1);
    }

    /// @dev Calculate proper initial values from randoms to initiate a balanced protocol
    function _randInitBalanced(uint128 initialDeposit, uint128 initialLong)
        internal
        returns (uint256 initialLeverage_)
    {
        // initial default params
        params = DEFAULT_PARAMS;
        params.enableLimits = true;

        // cannot be less than 1 ether
        initialDeposit = uint128(bound(initialDeposit, uint128(1 ether), uint128(5000 ether)));
        // cannot be less than 1 ether
        initialLong = uint128(bound(initialLong, uint128(1 ether), uint128(5000 ether)));

        // min long expo to initiate a balanced protocol
        uint256 minLongExpo = initialDeposit - initialDeposit * 2 / 100;
        // max long expo to initiate a balanced protocol
        uint256 maxLongExpo = initialDeposit + initialDeposit * 2 / 100;

        // initial leverage
        uint128 initialLeverage = uint128(
            10 ** LEVERAGE_DECIMALS * uint256(params.initialPrice)
                / (uint256(params.initialPrice) - uint256(params.initialPrice / 2))
        );

        // min long amount
        uint256 minLongAmount = uint128(
            uint256(minLongExpo) * 10 ** LEVERAGE_DECIMALS / (uint256(initialLeverage) - 10 ** LEVERAGE_DECIMALS)
        );
        // max long amount
        uint256 maxLongAmount = uint128(
            uint256(maxLongExpo) * 10 ** LEVERAGE_DECIMALS / (uint256(initialLeverage) - 10 ** LEVERAGE_DECIMALS)
        );

        // assign initial long amount in range min max
        initialLong = uint128(bound(initialLong, uint128(minLongAmount), uint128(maxLongAmount)));

        // calculation doesn't take count of min allowed by the protocol
        if (initialLong < 1 ether) {
            initialLong = 1 ether;
        }

        // assign initial values
        params.initialDeposit = initialDeposit;
        params.initialLong = initialLong;

        // init protocol
        _setUp(params);

        // initial leverage
        initialLeverage_ = protocol.i_getLeverage(params.initialPrice, params.initialPrice / 2);
    }
}
