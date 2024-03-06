// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ADMIN } from "test/utils/Constants.sol";
import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { IUsdnEvents } from "src/interfaces/Usdn/IUsdnEvents.sol";

/**
 * @custom:feature Test the rebasing of the USDN token depending on its price
 * @custom:background Given a protocol instance that was initialized with more expo in the long side and rebase enabled
 */
contract TestUsdnProtocolRebase is UsdnProtocolBaseFixture, IUsdnEvents {
    function setUp() public {
        params = DEFAULT_PARAMS;
        params.initialDeposit = 1 ether;
        params.initialLong = 10 ether;
        params.enableUsdnRebase = true;
        super._setUp(params);
        vm.prank(ADMIN);
        protocol.setProtocolFeeBps(0);
    }

    function test_usdnRebase() public {
        // initial price is $1
        assertEq(protocol.usdnPrice(params.initialPrice), 10 ** protocol.getPriceFeedDecimals());

        skip(1 hours);

        // price goes above rebase threshold due to funding
        uint256 usdnPrice = protocol.usdnPrice(params.initialPrice);
        assertGt(usdnPrice, protocol.getUsdnRebaseThreshold(), "initial price");

        // calculate expected new USDN divisor
        uint256 expectedVaultBalance =
            uint256(protocol.vaultAssetAvailableWithFunding(params.initialPrice, uint128(block.timestamp - 30)));
        uint256 expectedTotalSupply = protocol.i_calcRebaseTotalSupply(
            expectedVaultBalance,
            params.initialPrice,
            protocol.getTargetUsdnPrice(),
            protocol.getUsdnDecimals(),
            protocol.getAssetDecimals()
        );
        uint256 expectedDivisor = usdn.totalSupply() * usdn.divisor() / expectedTotalSupply;

        // vm.expectEmit();
        // emit Rebase(usdn.MAX_DIVISOR(), expectedDivisor);
        protocol.liquidate(abi.encode(params.initialPrice), 0);

        assertApproxEqAbs(
            protocol.usdnPrice(params.initialPrice, uint128(block.timestamp - 30)),
            protocol.getTargetUsdnPrice(),
            1,
            "price after rebase"
        );
        // assertEq(protocol.getBalanceVault(), expectedVaultBalance, "vault balance");
    }
}
