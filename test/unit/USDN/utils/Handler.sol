// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2, Test } from "forge-std/Test.sol";

import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { Usdn } from "src/Usdn.sol";

/**
 * @title UsdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract UsdnHandler is Usdn, Test {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // track theoretical shares
    EnumerableMap.AddressToUintMap private shares;

    // track theoretical total supply
    uint256 public totalSharesSum;

    constructor() Usdn(address(0), address(0)) { }

    function approve(address _owner, address _spender, uint256 _value) external {
        _approve(_owner, _spender, _value);
    }

    function transfer(address _from, address _to, uint256 _value) external {
        _transfer(_from, _to, _value);
    }

    function burn(address _owner, uint256 _value) external {
        _burn(_owner, _value);
    }

    /* ------------------ Functions used for invariant testing ------------------ */

    function getSharesOfAddress(address account) external view returns (uint256) {
        return EnumerableMap.get(shares, account);
    }

    function getLenghtOfShares() external view returns (uint256) {
        return EnumerableMap.length(shares);
    }

    function getSharesOfIndex(uint256 index) external view returns (uint256) {
        (, uint256 valueShares) = EnumerableMap.at(shares, index);
        return valueShares;
    }

    function rebaseTest(uint256 newDivisor) external {
        if (_divisor == MIN_DIVISOR) {
            return;
        }
        console2.log("bound divisor");
        newDivisor = bound(newDivisor, MIN_DIVISOR, _divisor - 1);
        emit Rebase(_divisor, newDivisor);
        _divisor = newDivisor;
    }

    function mintTest(uint256 value) external {
        if (totalSupply() >= maxTokens() - 1) {
            return;
        }
        console2.log("bound mint value");
        value = bound(value, 1, maxTokens() - totalSupply() - 1);
        uint256 valueShares = value * _divisor;
        totalSharesSum += valueShares;
        uint256 lastShares;
        if (EnumerableMap.contains(shares, msg.sender)) {
            lastShares = EnumerableMap.get(shares, msg.sender);
        } else {
            lastShares = 0;
        }
        EnumerableMap.set(shares, msg.sender, lastShares + valueShares);
        _mint(msg.sender, value);
    }

    function burnTest(uint256 value) external {
        if (balanceOf(msg.sender) == 0) {
            return;
        }
        console2.log("bound burn value");
        value = bound(value, 1, balanceOf(msg.sender));
        uint256 valueShares = value * _divisor;

        uint256 lastShares = EnumerableMap.get(shares, msg.sender);
        if (valueShares > lastShares) {
            valueShares = lastShares;
        }
        totalSharesSum -= valueShares;
        EnumerableMap.set(shares, msg.sender, lastShares - valueShares);
        _burn(msg.sender, value);
    }

    function transferTest(address to, uint256 value) external {
        console2.log("bound 'to' actor ID");
        if (balanceOf(msg.sender) == 0 || to == address(0)) {
            return;
        }
        console2.log("bound transfer value");
        value = bound(value, 1, balanceOf(msg.sender));
        uint256 valueShares = value * _divisor;
        uint256 lastShares = EnumerableMap.get(shares, msg.sender);
        if (valueShares > lastShares) {
            valueShares = lastShares;
        }

        EnumerableMap.set(shares, msg.sender, lastShares - valueShares);
        if (EnumerableMap.contains(shares, to)) {
            EnumerableMap.set(shares, to, EnumerableMap.get(shares, to) + valueShares);
        } else {
            EnumerableMap.set(shares, to, valueShares);
        }

        _transfer(msg.sender, to, value);
    }
}
