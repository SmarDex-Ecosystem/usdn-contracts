// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "test/unit/UsdnProtocol/utils/Fixtures.sol";
import { DEPLOYER, ADMIN } from "test/utils/Constants.sol";

import { ProtocolAction } from "src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @custom:feature The previewWithdraw function of the UsdnProtocolVault contract
 * @custom:background Given a protocol initialized with default params and enabledFunding = false
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolCalculateAssetTransferredForWithdraw is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        super._setUp(params);
        usdn.approve(address(protocol), type(uint256).max);
        // user deposits wstETH at price $2000
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, DEPOSIT_AMOUNT, 2000 ether);
    }

    /**
     * @custom:scenario Check calculations of `previewWithdraw`
     * @custom:given A user who deposited 1 wstETH at price $2000 to get 2000 USDN
     * @custom:when The user simulate withdraw of an amount of usdnShares from the vault
     * @custom:then The amount of asset should be calculated correctly
     */
    function test_previewWithdraw() public {
        uint256 price = 2000 ether;
        uint128 timestamp = uint128(block.timestamp);
        uint256 assetExpected = protocol.previewWithdraw(uint152(usdn.sharesOf(address(this))), price, timestamp);
        assertEq(assetExpected, DEPOSIT_AMOUNT + 259_596_326_121_494, "asset to transfer total share");

        assetExpected = protocol.previewWithdraw(uint152(2000 ether), price, timestamp);
        assertEq(assetExpected, 1, "asset to transfer just one asset");

        assetExpected = protocol.previewWithdraw(uint152(24_860_000_000 ether), price, timestamp);
        assertEq(assetExpected, 12_430_000 + 3226, "asset to transfer for 24860000000 ether shares");
    }

    /**
     * @custom:scenario Fuzzing the `previewWithdraw` and `withdraw` functions
     * @custom:given A user who deposited 1 wstETH at price $2000 to get 2000 USDN
     * @custom:when The user withdraw an amount of USDN shares from the vault
     * @custom:then The amount of asset should be calculated correctly
     */
    function testFuzz_comparepreviewWithdrawAndWithdraw(uint152 shares) public {
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        shares = uint152(bound(shares, 1, usdn.sharesOf(address(this))));

        // calculate the expected asset to be received
        uint256 assetExpected = protocol.previewWithdraw(shares, 2000 ether, uint128(block.timestamp));

        protocol.initiateWithdrawal(shares, currentPrice, EMPTY_PREVIOUS_DATA, address(this));
        // wait the required delay between initiation and validation
        _waitDelay();
        protocol.validateWithdrawal(currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(wstETH.balanceOf(address(this)), assetExpected, "wstETH user balance after withdraw");
    }
}
