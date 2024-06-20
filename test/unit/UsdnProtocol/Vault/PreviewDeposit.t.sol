// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolBaseFixture } from "../utils/Fixtures.sol";

/**
 * @custom:feature The previewDeposit function of the UsdnProtocolVault contract
 * @custom:background Given a protocol initialized with default params
 * @custom:and enableFunding = true, enablePositionFees = true and enableSdexBurnOnDeposit = true
 */
contract TestUsdnProtocolPreviewDeposit is UsdnProtocolBaseFixture {
    using SafeCast for uint256;

    function setUp() public {
        params = DEFAULT_PARAMS;
        params.flags.enableFunding = true;
        params.flags.enablePositionFees = true;
        params.flags.enableSdexBurnOnDeposit = true;
        super._setUp(params);
        wstETH.mintAndApprove(address(this), 1e9 ether, address(protocol), type(uint256).max);
        sdex.mintAndApprove(address(this), type(uint256).max, address(protocol), type(uint256).max);
    }

    /**
     * @custom:scenario Fuzzing the `previewDeposit` and `deposit` functions
     * @custom:given A protocol initialized with default params
     * @custom:when The user deposits an amount of wstETH to the vault
     * @custom:then The amount of USDN and SDEX tokens should be calculated correctly
     */
    function testFuzz_comparePreviewDepositAndDeposit(uint256 amount) public {
        bytes memory currentPrice = abi.encode(uint128(params.initialPrice));
        amount = bound(amount, 1, wstETH.balanceOf(address(this)));

        uint256 sdexBalanceBefore = sdex.balanceOf(address(this));

        protocol.initiateDeposit(
            amount.toUint128(), address(this), payable(address(this)), NO_PERMIT2, currentPrice, EMPTY_PREVIOUS_DATA
        );

        // calculate the expected USDN and SDEX tokens to be minted and burned
        (uint256 usdnSharesExpected, uint256 sdexToBurn) =
            protocol.previewDeposit(amount, params.initialPrice, protocol.getLastUpdateTimestamp());

        // wait the required delay between initiation and validation
        _waitDelay();
        protocol.validateDeposit(payable(address(this)), currentPrice, EMPTY_PREVIOUS_DATA);

        assertEq(usdn.sharesOf(address(this)), usdnSharesExpected, "usdn user balance after deposit");
        assertEq(sdex.balanceOf(address(this)), sdexBalanceBefore - sdexToBurn, "sdex user balance after deposit");
    }
}
