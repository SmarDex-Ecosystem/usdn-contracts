// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The calcAssetToWithdraw function of the UsdnProtocolVault contract
 * @custom:background Given a protocol initialized with default params and enabledFunding = false
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolCalculateAssetTransferredForWithdraw is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = false;
        super._setUp(params);
        usdn.approve(address(protocol), type(uint256).max);
        // user deposits wstETH at price $2000
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, DEPOSIT_AMOUNT, 2000 ether);
    }

    /**
     * @custom:scenario Check calculations of `calcAssetToWithdraw`
     * @custom:given A user who deposited 1 wstETH at price $2000 to get 2000 USDN
     * @custom:when The user simulate withdraw of an amount of usdnShares from the vault
     * @custom:then The amount of asset should be calculated correctly
     */
    function test_calcAssetToWithdraw() public {
        uint256 assetExpected = protocol.calcAssetToWithdraw(uint152(usdn.sharesOf(address(this))), 2000 ether);
        assertEq(assetExpected, DEPOSIT_AMOUNT, "asset to transfer");

        assetExpected = protocol.calcAssetToWithdraw(uint152(2000 ether), 2000 ether);
        assertEq(assetExpected, 1, "asset to transfer");

        assetExpected = protocol.calcAssetToWithdraw(uint152(24_860_000_000 ether), 2000 ether);
        assertEq(assetExpected, 12_430_000, "asset to transfer");
    }
}
