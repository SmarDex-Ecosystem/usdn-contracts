// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";

/**
 * @custom:feature Test the rebasing of the USDN token depending on its price
 * @custom:background Given a protocol instance that was initialized with more expo in the long side and rebase+funding
 * enabled
 */
contract TestUsdnProtocolRebase is UsdnProtocolBaseFixture, IUsdnEvents {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 5 ether;
        params.initialLong = 10 ether;
        params.enablePositionFees = false;
        params.enableProtocolFees = false;
        params.enableFunding = false;
        params.enableUsdnRebase = true;
        super._setUp(params);
        vm.prank(ADMIN);
        protocol.setProtocolFeeBps(0);
    }

    function test_usdnRebase() public {
        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals());

        skip(1 hours);

        uint128 newPrice = params.initialPrice - 100 ether;

        // price goes above rebase threshold due to change in asset price
        uint256 usdnPrice = protocol.usdnPrice(newPrice);
        assertGt(usdnPrice, protocol.getUsdnRebaseThreshold(), "initial price");

        // calculate expected new USDN divisor
        uint256 expectedVaultBalance =
            uint256(protocol.vaultAssetAvailableWithFunding(newPrice, uint128(block.timestamp - 30)));
        uint256 expectedTotalSupply = protocol.i_calcRebaseTotalSupply(
            expectedVaultBalance,
            newPrice,
            protocol.getTargetUsdnPrice(),
            protocol.getUsdnDecimals(),
            protocol.getAssetDecimals()
        );
        uint256 expectedDivisor = usdn.totalSupply() * usdn.divisor() / expectedTotalSupply;

        // rebase (no liquidation happens)
        vm.expectEmit();
        emit Rebase(usdn.MAX_DIVISOR(), expectedDivisor);
        protocol.liquidate(abi.encode(newPrice), 0);

        assertApproxEqAbs(
            protocol.usdnPrice(newPrice, uint128(block.timestamp - 30)),
            protocol.getTargetUsdnPrice(),
            1,
            "price after rebase"
        );
        assertApproxEqRel(usdn.totalSupply(), expectedTotalSupply, 1, "total supply");
        assertEq(protocol.getBalanceVault(), expectedVaultBalance, "vault balance");
    }
}
