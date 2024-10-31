// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { ADMIN, DEPLOYER } from "../../utils/Constants.sol";
import { IUsdnProtocolHandler } from "../../utils/IUsdnProtocolHandler.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";
import { UsdnProtocolHandler } from "./utils/Handler.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../../src/UsdnProtocol/UsdnProtocolFallback.sol";
import { HugeUint } from "../../../src/libraries/HugeUint.sol";

/**
 * @custom:feature Test the functions linked to initialization of the protocol
 * @custom:given An uninitialized protocol
 */
contract TestUsdnProtocolInitialize is UsdnProtocolBaseFixture {
    uint128 public constant INITIAL_DEPOSIT = 100 ether;
    uint128 public constant INITIAL_POSITION = 100 ether;
    uint128 public constant INITIAL_PRICE = 3000 ether;

    function setUp() public {
        super._setUp(DEFAULT_PARAMS);
        vm.startPrank(ADMIN);
        usdn = new Usdn(address(0), address(0));

        UsdnProtocolFallback protocolFallback = new UsdnProtocolFallback();
        UsdnProtocolHandler test = new UsdnProtocolHandler();
        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(test),
            abi.encodeCall(
                UsdnProtocolHandler.initializeStorageHandler,
                (
                    usdn,
                    sdex,
                    wstETH,
                    oracleMiddleware,
                    liquidationRewardsManager,
                    100, // tick spacing 100 = ~1.005%
                    ADMIN, // Fee collector
                    protocolFallback,
                    "1"
                )
            )
        );
        protocol = IUsdnProtocolHandler(proxy);

        usdn.grantRole(usdn.MINTER_ROLE(), address(protocol));
        usdn.grantRole(usdn.REBASER_ROLE(), address(protocol));

        protocol.beginDefaultAdminTransfer(address(this));
        vm.stopPrank();
        skip(1);
        protocol.acceptDefaultAdminTransfer();
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);

        _giveRolesAddressThis();
    }

    /**
     * @custom:scenario Deployer creates an initial deposit via the internal function
     * @custom:when The deployer calls the internal function to create an initial deposit
     * @custom:then The deployer's wstETH balance is decreased by the deposit amount
     * @custom:and The protocol's wstETH balance is increased by the deposit amount
     * @custom:and The deployer's USDN balance is increased by the minted amount
     * @custom:and The dead address' USDN balance is increased by the minimum USDN supply
     * @custom:and The vault balance is equal to the deposit amount
     * @custom:and The `InitiatedDeposit` event is emitted
     * @custom:and The `ValidatedDeposit` event is emitted for the dead address
     * @custom:and The `ValidatedDeposit` event is emitted for the deployer
     */
    function test_createInitialDeposit() public {
        uint256 expectedUsdnMinted = (
            uint256(INITIAL_DEPOSIT) * INITIAL_PRICE
                / 10 ** (protocol.getAssetDecimals() + protocol.getPriceFeedDecimals() - protocol.TOKENS_DECIMALS())
        ) - protocol.MIN_USDN_SUPPLY();
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit InitiatedDeposit(address(this), address(this), INITIAL_DEPOSIT, 0, block.timestamp, 0);
        vm.expectEmit();
        emit ValidatedDeposit(
            protocol.DEAD_ADDRESS(), protocol.DEAD_ADDRESS(), 0, protocol.MIN_USDN_SUPPLY(), block.timestamp
        );
        vm.expectEmit();
        emit ValidatedDeposit(address(this), address(this), INITIAL_DEPOSIT, expectedUsdnMinted, block.timestamp);
        protocol.i_createInitialDeposit(INITIAL_DEPOSIT, INITIAL_PRICE);

        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore - INITIAL_DEPOSIT, "deployer wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), INITIAL_DEPOSIT, "protocol wstETH balance");
        assertEq(usdn.balanceOf(address(this)), expectedUsdnMinted, "deployer USDN balance");
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "dead address USDN balance");
        assertEq(protocol.getBalanceVault(), INITIAL_DEPOSIT, "vault balance");
    }

    /**
     * @custom:scenario Deployer creates an initial position via the internal function
     * @custom:when The deployer calls the internal function to create an initial position
     * @custom:then The deployer's wstETH balance is decreased by the position amount
     * @custom:and The protocol's wstETH balance is increased by the position amount
     * @custom:and The `InitiatedOpenPosition` event is emitted
     * @custom:and The `ValidatedOpenPosition` event is emitted
     * @custom:and The position is stored in the protocol
     */
    function test_createInitialPosition() public {
        int24 tickWithoutPenalty = protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        int24 expectedTick = tickWithoutPenalty + int24(protocol.getLiquidationPenalty());
        uint128 posTotalExpo = 2 * INITIAL_POSITION;
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this),
            address(this),
            uint40(block.timestamp),
            posTotalExpo,
            INITIAL_POSITION,
            INITIAL_PRICE,
            PositionId(expectedTick, 0, 0)
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(
            address(this), address(this), posTotalExpo, INITIAL_PRICE, PositionId(expectedTick, 0, 0)
        );
        protocol.i_createInitialPosition(INITIAL_POSITION, INITIAL_PRICE, expectedTick, posTotalExpo);

        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore - INITIAL_POSITION, "deployer wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), INITIAL_POSITION, "protocol wstETH balance");
        assertEq(protocol.getBalanceLong(), INITIAL_POSITION, "protocol long balance");

        (Position memory pos,) = protocol.getLongPosition(PositionId(expectedTick, 0, 0));
        assertEq(pos.user, address(this), "position user");
        assertEq(pos.amount, INITIAL_POSITION, "position amount");
        assertEq(pos.totalExpo, posTotalExpo, "position total expo");
        assertEq(pos.timestamp, block.timestamp, "position timestamp");
    }

    /**
     * @custom:scenario Balanced protocol initialization
     * @custom:given Imbalance checks are 2% for deposit and 2% for open long
     * @custom:and The minLongPosition setting is at 0
     * @custom:when The deployer initializes the protocol with balanced amounts
     * @custom:then The transaction completes successfully
     */
    function test_checkInitImbalance() public {
        protocol.setExpoImbalanceLimits(200, 200, 0, 0, 0, 0); // 2%
        protocol.setMinLongPosition(0);

        uint128 depositAmount = 100 ether;
        uint128 longAmount = 100 ether;
        protocol.i_checkInitImbalance(longAmount * 2, longAmount, depositAmount);

        depositAmount = 102 ether;
        protocol.i_checkInitImbalance(longAmount * 2, longAmount, depositAmount);

        depositAmount = 100 ether;
        longAmount = 102 ether;
        protocol.i_checkInitImbalance(longAmount * 2, longAmount, depositAmount);
    }

    /**
     * @custom:scenario Imbalanced protocol initialization with disabled imbalance checks
     * @custom:given Imbalance checks are disabled
     * @custom:when The deployer initializes the protocol with imbalanced amounts
     * @custom:then The transaction completes successfully
     */
    function test_checkInitImbalanceDisabled() public {
        protocol.setExpoImbalanceLimits(0, 0, 0, 0, 0, 0); // disabled

        uint128 depositAmount = 1000 ether;
        uint128 longAmount = 100 ether;
        protocol.i_checkInitImbalance(longAmount * 2, longAmount, depositAmount);

        depositAmount = 100 ether;
        longAmount = 1000 ether;
        protocol.i_checkInitImbalance(longAmount * 2, longAmount, depositAmount);
    }

    /**
     * @custom:scenario Imbalanced protocol initialization with too big deposit
     * @custom:given Imbalance checks are 2% for deposits
     * @custom:when The deployer initializes the protocol with a deposit amount that is too big
     * @custom:then The transaction reverts with the error `UsdnProtocolImbalanceLimitReached`
     */
    function test_RevertWhen_checkInitImbalanceDepositTooBig() public {
        protocol.setExpoImbalanceLimits(0, 200, 0, 0, 0, 0); // 2% for deposit

        uint128 depositAmount = 102.01 ether;
        uint128 longAmount = 100 ether;

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolImbalanceLimitReached.selector, 201));
        protocol.i_checkInitImbalance(longAmount * 2, longAmount, depositAmount);
    }

    /**
     * @custom:scenario Imbalanced protocol initialization with too big long position
     * @custom:given Imbalance checks are 2% for open long
     * @custom:when The deployer initializes the protocol with a long amount that is too big
     * @custom:then The transaction reverts with the error `UsdnProtocolImbalanceLimitReached`
     */
    function test_RevertWhen_checkInitImbalanceLongTooBig() public {
        protocol.setExpoImbalanceLimits(200, 0, 0, 0, 0, 0); // 2% for open

        uint128 depositAmount = 100 ether;
        uint128 longAmount = 102.01 ether;

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolImbalanceLimitReached.selector, 201));
        protocol.i_checkInitImbalance(longAmount * 2, longAmount, depositAmount);
    }

    /**
     * @custom:scenario Deployer initializes the protocol
     * @custom:when The deployer calls the `initialize` function
     * @custom:then The deployer's wstETH balance is decreased by the deposit and position amounts
     * @custom:and The protocol's wstETH balance is increased by the deposit and position amounts
     * @custom:and The deployer's USDN balance is increased by the minted amount
     * @custom:and The dead address' USDN balance is increased by the minimum USDN supply
     * @custom:and All the events are emitted
     * @custom:and The position is stored in the protocol
     */
    function test_initialize() public {
        uint256 expectedUsdnMinted = (
            uint256(INITIAL_DEPOSIT) * INITIAL_PRICE
                / 10 ** (protocol.getAssetDecimals() + protocol.getPriceFeedDecimals() - protocol.TOKENS_DECIMALS())
        ) - protocol.MIN_USDN_SUPPLY();
        (int24 expectedTick, uint128 liquidationPriceWithoutPenalty) = protocol.i_getTickFromDesiredLiqPrice(
            INITIAL_PRICE / 2,
            INITIAL_PRICE,
            0,
            HugeUint.wrap(0),
            protocol.getTickSpacing(),
            protocol.getLiquidationPenalty()
        );
        uint128 expectedPosTotalExpo =
            protocol.i_calcPositionTotalExpo(INITIAL_DEPOSIT, INITIAL_PRICE, liquidationPriceWithoutPenalty);
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit InitiatedDeposit(address(this), address(this), INITIAL_DEPOSIT, 0, block.timestamp, 0);
        vm.expectEmit();
        emit ValidatedDeposit(
            protocol.DEAD_ADDRESS(), protocol.DEAD_ADDRESS(), 0, protocol.MIN_USDN_SUPPLY(), block.timestamp
        );
        vm.expectEmit();
        emit ValidatedDeposit(address(this), address(this), INITIAL_DEPOSIT, expectedUsdnMinted, block.timestamp);
        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this),
            address(this),
            uint40(block.timestamp),
            expectedPosTotalExpo,
            INITIAL_POSITION,
            INITIAL_PRICE,
            PositionId(expectedTick, 0, 0)
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(
            address(this), address(this), expectedPosTotalExpo, INITIAL_PRICE, PositionId(expectedTick, 0, 0)
        );
        protocol.initialize(INITIAL_DEPOSIT, INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));

        assertEq(
            wstETH.balanceOf(address(this)),
            assetBalanceBefore - INITIAL_DEPOSIT - INITIAL_POSITION,
            "deployer wstETH balance"
        );
        assertEq(wstETH.balanceOf(address(protocol)), INITIAL_DEPOSIT + INITIAL_POSITION, "protocol wstETH balance");
        assertEq(usdn.balanceOf(address(this)), expectedUsdnMinted, "deployer USDN balance");
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "dead address USDN balance");

        (Position memory pos,) = protocol.getLongPosition(PositionId(expectedTick, 0, 0));
        assertEq(pos.user, address(this), "position user");
        assertEq(pos.amount, INITIAL_POSITION, "position amount");
        assertEq(pos.totalExpo, expectedPosTotalExpo, "position total expo");
        assertEq(pos.timestamp, block.timestamp, "position timestamp");
    }

    /**
     * @custom:scenario Initialize with a deposit amount so low that a position cannot be opened afterwards
     * @custom:given A minLongPosition amount of 2 ether
     * @custom:and An imbalance limit of 2% for deposits
     * @custom:when The deployer calls the `initialize` function with a deposit amount too low
     * @custom:then The transaction reverts with the error `UsdnProtocolMinInitAmount`
     */
    function test_RevertWhen_initializeDepositAmountLow() public {
        protocol.setExpoImbalanceLimits(0, 200, 0, 0, 0, 0); // 2% for deposit
        protocol.setMinLongPosition(2 ether);

        uint128 minInitAmount = uint128(protocol.getMinLongPosition() * 2);
        uint128 initialDeposit =
            uint128(BPS_DIVISOR * minInitAmount / uint256(protocol.getDepositExpoImbalanceLimitBps()));
        uint128 initialLong = initialDeposit;

        int24 tick = protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        uint128 price = protocol.getEffectivePriceForTick(tick);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolMinInitAmount.selector));
        protocol.initialize(initialDeposit - 1 ether, initialLong - 1 ether, price, abi.encode(price * 2));
    }

    /**
     * @custom:scenario Initialize with a long amount so low that a position cannot be opened afterwards
     * @custom:given a minLongPosition amount of 2 ether
     * @custom:and An imbalance limit of 2% for opening long positions
     * @custom:when The deployer calls the `initialize` function with a long amount too low
     * @custom:then The transaction reverts with the error `UsdnProtocolMinInitAmount`
     */
    function test_RevertWhen_initializeLongAmountLow() public {
        protocol.setExpoImbalanceLimits(200, 0, 0, 0, 0, 0); // 2% for open
        protocol.setMinLongPosition(2 ether);

        uint128 minInitAmount = uint128(protocol.getMinLongPosition() * 2);
        uint128 initialLong = uint128(BPS_DIVISOR * minInitAmount / uint256(protocol.getOpenExpoImbalanceLimitBps()));
        uint128 initialDeposit = initialLong;

        int24 tick = protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        uint128 price = protocol.getEffectivePriceForTick(tick);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolMinInitAmount.selector));
        protocol.initialize(initialDeposit - 1 ether, initialLong - 1 ether, price, abi.encode(price * 2));
    }

    /**
     * @custom:scenario Initialize while some USDN that was minted previously
     * @custom:given Some USDN was minted before initialization
     * @custom:when The deployer calls the `initialize` function
     * @custom:then The transaction reverts with the error `UsdnProtocolInvalidUsdn`
     */
    function test_RevertWhen_initializeUsdnSupply() public {
        vm.prank(address(protocol));
        usdn.mint(address(this), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolInvalidUsdn.selector, address(usdn)));
        protocol.initialize(INITIAL_DEPOSIT, INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));
    }

    /**
     * @custom:scenario Send too much ether while initializing
     * @custom:given The oracle is free to use
     * @custom:when The deployer sends ether while initializing the protocol
     * @custom:then The protocol refunds the excess ether and the balance remains the same
     */
    function test_initializeRefundEther() public {
        uint256 balanceBefore = address(this).balance;
        protocol.initialize{ value: 1 ether }(
            INITIAL_DEPOSIT, INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE)
        );
        assertEq(address(this).balance, balanceBefore, "balance");
    }

    /**
     * @custom:scenario Frontrun the protocol initialization by calling the `initialize` function with a non-admin
     * address
     * @custom:when The attacker calls the `initialize` function
     * @custom:then The transaction reverts with the error `AccessControlUnauthorizedAccount`
     */
    function test_RevertWhen_Frontrun() public {
        bytes32 DEFAULT_ADMIN_ROLE = 0x00;
        vm.prank(address(0));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(0), DEFAULT_ADMIN_ROLE
            )
        );
        protocol.initialize(INITIAL_DEPOSIT, INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));
    }

    /**
     * @custom:scenario Owner initialize protocol with position that has a leverage too low
     * @custom:when Owner initialize an open position with a leverage of 1.033
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooLow
     */
    function test_RevertWhen_initializePositionLowLeverage() public {
        vm.expectRevert(UsdnProtocolLeverageTooLow.selector);
        protocol.initialize(INITIAL_DEPOSIT, INITIAL_POSITION * 30, INITIAL_PRICE / 31, abi.encode(INITIAL_PRICE));
    }

    /**
     * @custom:scenario Owner initialize protocol with position that has a leverage too high
     * @custom:when Owner initialize an open position with a leverage of 10.8
     * @custom:then The protocol reverts with UsdnProtocolLeverageTooHigh
     */
    function test_RevertWhen_initializePositionHighLeverage() public {
        vm.expectRevert(UsdnProtocolLeverageTooHigh.selector);
        protocol.initialize(
            INITIAL_DEPOSIT, INITIAL_POSITION / 10, (INITIAL_PRICE * 10) / 11, abi.encode(INITIAL_PRICE)
        );
    }

    function _giveRolesAddressThis() internal {
        vm.prank(ADMIN);
        protocol.grantRole(protocol.ADMIN_CRITICAL_FUNCTIONS_ROLE(), address(this));
        protocol.grantRole(protocol.ADMIN_SET_EXTERNAL_ROLE(), address(this));
        protocol.grantRole(protocol.ADMIN_SET_PROTOCOL_PARAMS_ROLE(), address(this));
        protocol.grantRole(protocol.ADMIN_SET_USDN_PARAMS_ROLE(), address(this));
        protocol.grantRole(protocol.ADMIN_SET_OPTIONS_ROLE(), address(this));
        protocol.grantRole(protocol.ADMIN_PROXY_UPGRADE_ROLE(), address(this));
        protocol.grantRole(protocol.ADMIN_PAUSER_ROLE(), address(this));
        protocol.grantRole(protocol.ADMIN_UNPAUSER_ROLE(), address(this));
        vm.stopPrank();

        protocol.grantRole(protocol.CRITICAL_FUNCTIONS_ROLE(), address(this));
        protocol.grantRole(protocol.SET_EXTERNAL_ROLE(), address(this));
        protocol.grantRole(protocol.SET_PROTOCOL_PARAMS_ROLE(), address(this));
        protocol.grantRole(protocol.SET_USDN_PARAMS_ROLE(), address(this));
        protocol.grantRole(protocol.SET_OPTIONS_ROLE(), address(this));
        protocol.grantRole(protocol.PROXY_UPGRADE_ROLE(), address(this));
        protocol.grantRole(protocol.PAUSER_ROLE(), address(this));
        protocol.grantRole(protocol.UNPAUSER_ROLE(), address(this));
    }

    receive() external payable { }
}
