// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";

import { Usdn } from "src/Usdn.sol";
import { InitializableReentrancyGuard } from "src/utils/InitializableReentrancyGuard.sol";
import { Position } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

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
        vm.startPrank(DEPLOYER);
        usdn = new Usdn(address(0), address(0));

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

        protocol.transferOwnership(address(this));
        vm.stopPrank();
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), type(uint256).max);
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
        emit InitiatedDeposit(address(this), address(this), INITIAL_DEPOSIT, block.timestamp);
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
     * @custom:scenario Initial deposit internal function cannot be called once the protocol has been initialized
     * @custom:given The protocol has been initialized
     * @custom:when The deployer calls the internal function to create an initial deposit
     * @custom:then The transaction reverts with the error `InitializableReentrancyGuardInvalidInitialization`
     */
    function test_RevertWhen_createInitialDepositAlreadyInitialized() public {
        protocol.initialize(INITIAL_DEPOSIT, INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));

        vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector);
        protocol.i_createInitialDeposit(INITIAL_DEPOSIT, INITIAL_PRICE);
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
        int24 expectedTick =
            tickWithoutPenalty + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        uint128 leverage = uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS());
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit InitiatedOpenPosition(
            address(this),
            address(this),
            uint40(block.timestamp),
            leverage,
            INITIAL_POSITION,
            INITIAL_PRICE,
            expectedTick,
            0,
            0
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(address(this), address(this), leverage, INITIAL_PRICE, expectedTick, 0, 0);
        protocol.i_createInitialPosition(
            INITIAL_POSITION, INITIAL_PRICE, tickWithoutPenalty, leverage, 2 * INITIAL_POSITION
        );

        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore - INITIAL_POSITION, "deployer wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), INITIAL_POSITION, "protocol wstETH balance");
        assertEq(protocol.getBalanceLong(), INITIAL_POSITION, "protocol long balance");

        (Position memory pos,) = protocol.getLongPosition(expectedTick, 0, 0);
        assertEq(pos.user, address(this), "position user");
        assertEq(pos.amount, INITIAL_POSITION, "position amount");
        assertEq(pos.totalExpo, 2 * INITIAL_POSITION, "position total expo");
        assertEq(pos.timestamp, block.timestamp, "position timestamp");
    }

    /**
     * @custom:scenario Initial position internal function cannot be called once the protocol has been initialized
     * @custom:given The protocol has been initialized
     * @custom:when The deployer calls the internal function to create an initial position
     * @custom:then The transaction reverts with the error `InitializableReentrancyGuardInvalidInitialization`
     */
    function test_RevertWhen_createInitialPositionAlreadyInitialized() public {
        protocol.initialize(INITIAL_DEPOSIT, INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));

        int24 tickWithoutPenalty = protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        uint128 leverage = uint128(2 * 10 ** protocol.LEVERAGE_DECIMALS());

        vm.expectRevert(InitializableReentrancyGuard.InitializableReentrancyGuardInvalidInitialization.selector);
        protocol.i_createInitialPosition(
            INITIAL_POSITION, INITIAL_PRICE, tickWithoutPenalty, leverage, 2 * INITIAL_POSITION
        );
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
        int24 tickWithoutPenalty = protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        int24 expectedTick =
            tickWithoutPenalty + int24(uint24(protocol.getLiquidationPenalty())) * protocol.getTickSpacing();
        uint128 liquidationPriceWithoutPenalty = protocol.getEffectivePriceForTick(tickWithoutPenalty);
        uint128 leverage = protocol.i_getLeverage(INITIAL_PRICE, liquidationPriceWithoutPenalty);
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit InitiatedDeposit(address(this), address(this), INITIAL_DEPOSIT, block.timestamp);
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
            leverage,
            INITIAL_POSITION,
            INITIAL_PRICE,
            expectedTick,
            0,
            0
        );
        vm.expectEmit();
        emit ValidatedOpenPosition(address(this), address(this), leverage, INITIAL_PRICE, expectedTick, 0, 0);
        protocol.initialize(INITIAL_DEPOSIT, INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));

        assertEq(
            wstETH.balanceOf(address(this)),
            assetBalanceBefore - INITIAL_DEPOSIT - INITIAL_POSITION,
            "deployer wstETH balance"
        );
        assertEq(wstETH.balanceOf(address(protocol)), INITIAL_DEPOSIT + INITIAL_POSITION, "protocol wstETH balance");
        assertEq(usdn.balanceOf(address(this)), expectedUsdnMinted, "deployer USDN balance");
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "dead address USDN balance");

        (Position memory pos,) = protocol.getLongPosition(expectedTick, 0, 0);
        assertEq(pos.user, address(this), "position user");
        assertEq(pos.amount, INITIAL_POSITION, "position amount");
        assertEq(
            pos.totalExpo,
            uint256(leverage) * INITIAL_POSITION / 10 ** protocol.LEVERAGE_DECIMALS(),
            "position total expo"
        );
        assertEq(pos.timestamp, block.timestamp, "position timestamp");
    }

    /**
     * @custom:scenario Initialize with low amount for deposit
     * @custom:when The deployer calls the `initialize` function with a deposit amount lower than the minimum required
     * @custom:then The transaction reverts with the error `UsdnProtocolMinInitAmount`
     */
    function test_RevertWhen_initializeDepositAmountLow() public {
        uint256 minDeposit = protocol.MIN_INIT_DEPOSIT();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolMinInitAmount.selector, minDeposit));
        protocol.initialize(uint128(minDeposit - 1), INITIAL_POSITION, INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));
    }

    /**
     * @custom:scenario Initialize with low amount for long
     * @custom:when The deployer calls the `initialize` function with a long amount lower than the minimum required
     * @custom:then The transaction reverts with the error `UsdnProtocolMinInitAmount`
     */
    function test_RevertWhen_initializeLongAmountLow() public {
        uint256 minDeposit = protocol.MIN_INIT_DEPOSIT();
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolMinInitAmount.selector, minDeposit));
        protocol.initialize(INITIAL_DEPOSIT, uint128(minDeposit - 1), INITIAL_PRICE / 2, abi.encode(INITIAL_PRICE));
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

    receive() external payable { }
}
