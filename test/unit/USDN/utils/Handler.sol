// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test, console2 } from "forge-std/Test.sol";

import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import { Usdn } from "../../../../src/Usdn/Usdn.sol";

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

    /// @dev Used to generate unrealistic situations where the divisor is out of bounds
    function setDivisor(uint256 d) external {
        _divisor = d;
    }

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

    function i_burnShares(address owner, uint256 value, uint256 tokenValue) external {
        _burnShares(owner, value, tokenValue);
    }

    function i_updateShares(address from, address to, uint256 value, uint256 tokenValue) external {
        _updateShares(from, to, value, tokenValue);
    }

    function i_update(address from, address to, uint256 value) external {
        _update(from, to, value);
    }

    function i_convertToTokens(uint256 amountShares, Rounding rounding, uint256 d) external pure returns (uint256) {
        return _convertToTokens(amountShares, rounding, d);
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

    function mintSharesTest(uint256 value) external {
        if (_totalShares >= type(uint256).max) {
            return;
        }
        console2.log("bound mint shares value");
        value = bound(value, 1, type(uint256).max - _totalShares);
        totalSharesSum += value;
        (, uint256 lastShares) = _sharesHandle.tryGet(msg.sender);
        _sharesHandle.set(msg.sender, lastShares + value);
        _updateShares(address(0), msg.sender, value, _convertToTokens(value, Rounding.Closest, _divisor));
    }

    function burnSharesTest(uint256 value) external {
        if (sharesOf(msg.sender) == 0) {
            return;
        }
        console2.log("bound burn shares value");
        value = bound(value, 1, sharesOf(msg.sender));

        totalSharesSum -= value;

        uint256 lastShares = _sharesHandle.get(msg.sender);
        _sharesHandle.set(msg.sender, lastShares - value);
        _burnShares(msg.sender, value, _convertToTokens(value, Rounding.Closest, _divisor));
    }

    function transferSharesTest(address to, uint256 value) external {
        if (sharesOf(msg.sender) == 0 || to == address(0)) {
            return;
        }
        console2.log("bound transfer shares value");
        value = bound(value, 1, sharesOf(msg.sender));
        uint256 lastShares = _sharesHandle.get(msg.sender);
        _sharesHandle.set(msg.sender, lastShares - value);
        (, uint256 toShares) = _sharesHandle.tryGet(to);
        _sharesHandle.set(to, toShares + value);

        _transferShares(msg.sender, to, value, _convertToTokens(value, Rounding.Closest, _divisor));
    }
}
