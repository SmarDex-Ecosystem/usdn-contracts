// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { UnsafeUpgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

import { ADMIN, DEPLOYER } from "../../utils/Constants.sol";
import { IUsdnProtocolHandler } from "../../utils/IUsdnProtocolHandler.sol";
import { UsdnProtocolBaseFixture } from "./utils/Fixtures.sol";
import { UsdnProtocolHandler } from "./utils/Handler.sol";
import { TransferCallback } from "./utils/TransferCallback.sol";

import { Usdn } from "../../../src/Usdn/Usdn.sol";
import { UsdnProtocolFallback } from "../../../src/UsdnProtocol/UsdnProtocolFallback.sol";

/**
 * @custom:feature Test the functions linked to initialization of the protocol
 * @custom:given An uninitialized protocol
 */
contract TestUsdnProtocolInitialize is TransferCallback, UsdnProtocolBaseFixture {
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
                    protocolFallback
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
        wstETH.mintAndApprove(address(this), 10_000 ether, address(protocol), 0);

        _giveRolesTo(
            Managers(
                address(this),
                address(this),
                address(this),
                address(this),
                address(this),
                address(this),
                address(this),
                address(this)
            ),
            protocol
        );
    }

    /**
     * @custom:scenario Deployer creates an initial deposit via the internal function by using callback for the transfer
     * of wstETH
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
    function test_createInitialDepositWithCallback() public {
        transferActive = true;
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

    function test_RevertWhen_createInitialDepositWithCallbackNoTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.i_createInitialDeposit(INITIAL_DEPOSIT, INITIAL_PRICE);
    }

    /**
     * @custom:scenario Deployer creates an initial position via the internal function by using callback for the
     * transfer
     * of wstETH
     * @custom:when The deployer calls the internal function to create an initial position
     * @custom:then The deployer's wstETH balance is decreased by the position amount
     * @custom:and The protocol's wstETH balance is increased by the position amount
     * @custom:and The `InitiatedOpenPosition` event is emitted
     * @custom:and The `ValidatedOpenPosition` event is emitted
     * @custom:and The position is stored in the protocol
     */
    function test_createInitialPositionWithCallback() public {
        transferActive = true;
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

    function test_RevertWhen_createInitialPositionWithCallbackNoTransfer() public {
        int24 tickWithoutPenalty = protocol.getEffectiveTickForPrice(INITIAL_PRICE / 2);
        int24 expectedTick = tickWithoutPenalty + int24(protocol.getLiquidationPenalty());
        uint128 posTotalExpo = 2 * INITIAL_POSITION;

        vm.expectRevert(abi.encodeWithSelector(UsdnProtocolPaymentCallbackFailed.selector));
        protocol.i_createInitialPosition(INITIAL_POSITION, INITIAL_PRICE, expectedTick, posTotalExpo);
    }

    receive() external payable { }
}
