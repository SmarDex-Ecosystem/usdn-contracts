// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/**
 * @title StETHtoWstETH contract
 * @dev This contract is used to aqpply steth to wsteth ratio.
 */
contract StETHToWstETH {
    function stethToWsteth(uint256 amount, uint256 stEthPerToken) public pure returns (uint256) {
        return amount * 1 ether / stEthPerToken;
    }
}
