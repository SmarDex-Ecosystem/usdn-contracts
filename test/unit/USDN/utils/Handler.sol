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
    EnumerableMap.AddressToUintMap private _sharesHandle;

    // track theoretical total supply
    uint256 public totalSharesSum;

    constructor() Usdn(address(0), address(0)) { }

    function i_approve(address owner, address spender, uint256 value) external {
        _approve(owner, spender, value);
    }

    function i_transfer(address from, address to, uint256 value) external {
        _transfer(from, to, value);
    }

    function i_burn(address owner, uint256 value) external {
        _burn(owner, value);
    }

    function i_transferShares(address from, address to, uint256 value, uint256 tokenValue) external {
        _transferShares(from, to, value, tokenValue);
    }

    /* ------------------ Functions used for invariant testing ------------------ */

    function getSharesOfAddress(address account) external view returns (uint256) {
        (, uint256 valueShares) = _sharesHandle.tryGet(account);
        return valueShares;
    }

    function getElementOfIndex(uint256 index) external view returns (address, uint256) {
        return _sharesHandle.at(index);
    }

    function getLengthOfShares() external view returns (uint256) {
        return _sharesHandle.length();
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
        (, uint256 lastShares) = _sharesHandle.tryGet(msg.sender);
        _sharesHandle.set(msg.sender, lastShares + valueShares);
        _mint(msg.sender, value);
    }

    function burnTest(uint256 value) external {
        if (balanceOf(msg.sender) == 0) {
            return;
        }
        console2.log("bound burn value");
        value = bound(value, 1, balanceOf(msg.sender));
        uint256 valueShares = value * _divisor;

        uint256 lastShares = _sharesHandle.get(msg.sender);
        if (valueShares > lastShares) {
            valueShares = lastShares;
        }
        totalSharesSum -= valueShares;
        _sharesHandle.set(msg.sender, lastShares - valueShares);
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
        uint256 lastShares = _sharesHandle.get(msg.sender);
        if (valueShares > lastShares) {
            valueShares = lastShares;
        }
        _sharesHandle.set(msg.sender, lastShares - valueShares);
        (, uint256 toShares) = _sharesHandle.tryGet(to);
        _sharesHandle.set(to, toShares + valueShares);

        _transfer(msg.sender, to, value);
    }
}
