// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/Test.sol";

import { UsdnTokenFixture } from "test/unit/USDN/utils/Fixtures.sol";
import { USER_1 } from "test/utils/Constants.sol";

/**
 * @custom:feature Fuzzing and invariants of the USDN token
 * @custom:background Given TOKENS_MAX, a maximum amount of tokens that can exist
 */
contract TestUsdnFuzzing is UsdnTokenFixture {
    function setUp() public override {
        super.setUp();
        usdn.grantRole(usdn.MINTER_ROLE(), address(this));
        usdn.grantRole(usdn.ADJUSTMENT_ROLE(), address(this));
    }

    /**
     * @custom:scenario Convert an amount of tokens to the corresponding amount of shares, then back to tokens
     * @custom:given A multiplier between 1 and 1000
     * @custom:and An amount of tokens between 0 and MAX_TOKENS
     * @custom:when The tokens are converted to shares and back to tokens
     * @custom:then The result is the same as the original amount of tokens
     * @param multiplier The multiplier to use
     * @param tokens The amount of tokens to convert
     */
    function testFuzz_convertBetweenTokensAndShares(uint256 multiplier, uint256 tokens) public {
        multiplier = bound(multiplier, 1 gwei, 1 ether);
        tokens = bound(tokens, 0, usdn.maxTokens());

        if (multiplier > 1 gwei) {
            usdn.adjustMultiplier(multiplier);
        }

        uint256 shares = usdn.convertToShares(tokens);
        uint256 tokensOut = usdn.convertToTokens(shares);

        assertEq(tokens, tokensOut);
    }

    /**
     * @custom:scenario Transfer an amount of tokens to a user and check the balance changes
     * @custom:given A multiplier between 1 and 1000
     * @custom:and An amount of tokens between 0 and MAX_TOKENS
     * @custom:when The tokens are transferred to a user
     * @custom:then The balance of this contract is decreased by the amount of tokens
     * @custom:and The balance of the user is increased by the amount of tokens
     * @custom:and The `Transfer` event is emitted with the correct amount
     * @param multiplier The multiplier to use
     * @param transferAmount The amount of tokens to transfer
     */
    function testFuzz_balanceInvariant(uint256 multiplier, uint256 transferAmount) public {
        multiplier = bound(multiplier, 1 gwei, 1 ether);
        transferAmount = bound(transferAmount, 0, usdn.maxTokens());

        if (multiplier > 1 gwei) {
            usdn.adjustMultiplier(multiplier);
        }

        usdn.mint(address(this), usdn.maxTokens());
        uint256 balanceBefore = usdn.balanceOf(address(this));

        vm.expectEmit(true, true, true, false, address(usdn));
        emit Transfer(address(this), USER_1, transferAmount); // expected event
        usdn.transfer(USER_1, transferAmount);

        assertEq(usdn.balanceOf(address(this)), balanceBefore - transferAmount);
        assertEq(usdn.balanceOf(USER_1), transferAmount);
    }

    /**
     * @custom:scenario Check that the total supply is the sum of the balances of all holders
     * @custom:given A multiplier between 1 and 1000
     * @custom:and 10 holders with random balances
     * @custom:when The total supply is queried
     * @custom:then The result is the sum of the balances of all holders
     * @param multiplier The multiplier to use
     */
    function testFuzz_totalSupplyInvariant(uint256 multiplier) public {
        multiplier = bound(multiplier, 1 gwei, 1 ether);
        if (multiplier > 1 gwei) {
            usdn.adjustMultiplier(multiplier);
        }

        uint256 totalHolders = 10;
        uint256[] memory balances = new uint256[](totalHolders);
        uint256 totalBalances;
        for (uint256 i = 0; i < totalHolders; i++) {
            balances[i] =
                _bound(uint256(keccak256(abi.encodePacked(i + multiplier))), 0, usdn.maxTokens() / totalHolders);
            totalBalances += balances[i];
            usdn.mint(address(uint160(i + 1)), balances[i]);
        }
        assertEq(usdn.totalSupply(), totalBalances);
    }
}
