// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { Usdn } from "src/Usdn.sol";

/**
 * @title UsdnHandler
 * @dev Wrapper to test internal functions and access internal constants
 */
contract UsdnHandler is Usdn {
    constructor() Usdn(address(0), address(0)) { }

    function decimalsOffset() external pure returns (uint8) {
        return DECIMALS_OFFSET;
    }

    function maxTokens() external pure returns (uint256) {
        return MAX_TOKENS;
    }

    function approve(address _owner, address _spender, uint256 _value) external {
        _approve(_owner, _spender, _value);
    }

    function transfer(address _from, address _to, uint256 _value) external {
        _transfer(_from, _to, _value);
    }

    function burn(address _owner, uint256 _value) external {
        _burn(_owner, _value);
    }
}
