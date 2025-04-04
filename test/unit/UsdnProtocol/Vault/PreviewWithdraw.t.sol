// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";

/**
 * @custom:feature The previewWithdraw function of the UsdnProtocolVault contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and enableFunding = true and enablePositionFees = true
 * @custom:and A user who deposited 1 wstETH at price $2000 to get 2000 USDN
 */
contract TestUsdnProtocolPreviewWithdraw is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    uint128 internal constant DEPOSIT_AMOUNT = 1 ether;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        params.flags.enablePositionFees = true;
        super._setUp(params);
        usdn.approve(address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Check calculations of `previewWithdraw`
     * @custom:given The available vault balance (with vault fee applied) is greater than zero
     * @custom:when The user simulates the withdrawal a portion of the usdnShares from the vault
     * @custom:then The amount of asset should match the expected value
     */
    function testFuzz_previewWithdraw(uint256 shares) public view {
        uint128 price = 2000 ether;
        shares = bound(shares, 0, usdn.totalShares());
        uint256 expectedAmount = shares * protocol.getBalanceVault() * (BPS_DIVISOR - protocol.getPositionFeeBps())
            / (usdn.totalShares() * BPS_DIVISOR);

        assertEq(
            protocol.previewWithdraw(shares, price, protocol.getLastUpdateTimestamp()),
            expectedAmount,
            "asset is equal to expected"
        );
    }

    /**
     * @custom:scenario Check calculations of `previewWithdraw` when the available asset is less than zero
     * @custom:given A protocol initialized with default params
     * @custom:when The user simulate a withdrawal of an amount of usdnShares from the vault
     * @custom:then The amount of asset should be equal to zero
     */
    function test_previewWithdrawLessThanZero() public {
        uint128 price = 2000 ether;
        setUpUserPositionInLong(
            OpenParams({
                user: address(this),
                untilAction: ProtocolAction.ValidateOpenPosition,
                positionSize: 1000 ether,
                desiredLiqPrice: price * 90 / 100,
                price: price
            })
        );

        uint128 timestamp = protocol.getLastUpdateTimestamp();

        // Apply fees on price
        uint128 withdrawalPriceWithFees =
            (price * 10 + price * 10 * protocol.getPositionFeeBps() / Constants.BPS_DIVISOR).toUint128();
        uint256 available = protocol.vaultAssetAvailableWithFunding(withdrawalPriceWithFees, timestamp);
        assertEq(available, 0, "vaultAssetAvailableWithFunding should be equal to 0");

        uint256 assetExpected = protocol.previewWithdraw(uint152(usdn.sharesOf(address(this))), price * 10, timestamp);
        assertEq(assetExpected, 0, "asset is equal to zero");
    }

    /**
     * @custom:scenario Fuzzing the `previewWithdraw` and `withdraw` functions
     * @custom:given A user who deposited 1 wstETH at price $2000 to get 2000 USDN
     * @custom:when The user withdraws an amount of USDN shares from the vault
     * @custom:then The amount of asset should be calculated correctly
     */
    function testFuzz_comparePreviewWithdrawAndWithdraw(uint152 shares) public {
        // user deposits wstETH at a price of $2000
        setUpUserPositionInVault(address(this), ProtocolAction.ValidateDeposit, DEPOSIT_AMOUNT, 2000 ether);
        skip(1 hours);
        bytes memory currentPrice = abi.encode(uint128(2000 ether));
        shares = uint152(bound(shares, 1, usdn.sharesOf(address(this))));

        protocol.initiateWithdrawal(
            shares,
            DISABLE_AMOUNT_OUT_MIN,
            address(this),
            payable(address(this)),
            type(uint256).max,
            currentPrice,
            EMPTY_PREVIOUS_DATA
        );
        // calculate the expected asset to be received
        uint256 assetExpected = protocol.previewWithdraw(shares, 2000 ether, uint128(block.timestamp));
        // wait the required delay between initiation and validation
        _waitDelay();
        protocol.validateWithdrawal(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(wstETH.balanceOf(address(this)), assetExpected, "wstETH user balance after withdraw");
    }
}
