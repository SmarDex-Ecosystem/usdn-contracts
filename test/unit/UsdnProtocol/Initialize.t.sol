// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { ADMIN } from "test/utils/Constants.sol";
import { WstETH } from "test/utils/WstEth.sol";
import { Sdex } from "test/utils/Sdex.sol";
import { MockOracleMiddleware } from "test/unit/UsdnProtocol/utils/MockOracleMiddleware.sol";
import { MockChainlinkOnChain } from "test/unit/Middlewares/utils/MockChainlinkOnChain.sol";
import { UsdnProtocolHandler } from "test/unit/UsdnProtocol/utils/Handler.sol";

import { Usdn } from "src/Usdn.sol";
import { LiquidationRewardsManager } from "src/OracleMiddleware/LiquidationRewardsManager.sol";

/**
 * @custom:feature Test the functions linked to initialization of the protocol
 * @custom:given An uninitialized protocol
 */
contract TestUsdnProtocolInitialize is UsdnProtocolBaseFixture {
    uint128 public constant INITIAL_DEPOSIT = 100 ether;

    function setUp() public {
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

        wstETH.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Deployer creates an initial deposit via the internal function
     * @custom:when The deployer calls the internal function to create an initial deposit
     * @custom:then The deployer's wstETH balance is decreased by the deposit amount
     * @custom:and The protocol's wstETH balance is increased by the deposit amount
     * @custom:and The deployer's USDN balance is increased by the minted amount
     * @custom:and The dead address' USDN balance is increased by the minimum USDN supply
     * @custom:and The `InitiatedDeposit` event is emitted
     * @custom:and The `ValidatedDeposit` event is emitted for the dead address
     * @custom:and The `ValidatedDeposit` event is emitted for the deployer
     */
    function test_createInitialDeposit() public {
        uint128 price = 3000 ether;
        uint256 expectedUsdnMinted = (
            uint256(INITIAL_DEPOSIT) * price
                / 10 ** (protocol.getAssetDecimals() + protocol.getPriceFeedDecimals() - protocol.TOKENS_DECIMALS())
        ) - protocol.MIN_USDN_SUPPLY();
        uint256 assetBalanceBefore = wstETH.balanceOf(address(this));

        vm.expectEmit();
        emit InitiatedDeposit(address(this), INITIAL_DEPOSIT, block.timestamp);
        vm.expectEmit();
        emit ValidatedDeposit(protocol.DEAD_ADDRESS(), 0, protocol.MIN_USDN_SUPPLY(), block.timestamp);
        vm.expectEmit();
        emit ValidatedDeposit(address(this), INITIAL_DEPOSIT, expectedUsdnMinted, block.timestamp);
        protocol.i_createInitialDeposit(INITIAL_DEPOSIT, price);

        assertEq(wstETH.balanceOf(address(this)), assetBalanceBefore - INITIAL_DEPOSIT, "deployer wstETH balance");
        assertEq(wstETH.balanceOf(address(protocol)), INITIAL_DEPOSIT, "protocol wstETH balance");
        assertEq(usdn.balanceOf(address(this)), expectedUsdnMinted, "deployer USDN balance");
        assertEq(usdn.balanceOf(protocol.DEAD_ADDRESS()), protocol.MIN_USDN_SUPPLY(), "dead address USDN balance");
    }
}
