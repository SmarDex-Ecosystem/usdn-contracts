// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console, Test } from "forge-std/Test.sol";

import { Usdn } from "src/Usdn.sol";

/**
 * @title UsdnHandler
 * @dev Wrapper to test internal functions and access internal constants, as well as perform invariant testing
 */
contract UsdnHandler is Usdn, Test {
    // use multiple actors for invariant testing
    address[] public actors;

    // current actor
    address internal currentActor;

    // track theoretical balances
    mapping(address account => uint256) public balances;

    // track theorectical total supply
    uint256 public totalSupplySum;

    constructor(address[] memory _actors) Usdn(address(0), address(0)) {
        actors = _actors;
    }

    function maxDivisor() external pure returns (uint256) {
        return MAX_DIVISOR;
    }

    function minDivisor() external pure returns (uint256) {
        return MIN_DIVISOR;
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

    /* ------------------- Funtions used for invariant testing ------------------ */

    modifier useActor(uint256 actorIndexSeed) {
        console.log("bound actor ID");
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function adjustDivisorTest(uint256 _divisor) external {
        if (divisor == MIN_DIVISOR) {
            return;
        }
        console.log("bound divisor");
        _divisor = bound(_divisor, MIN_DIVISOR, divisor - 1);
        emit DivisorAdjusted(divisor, _divisor);
        divisor = _divisor;
    }

    function mintTest(uint256 value, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        if (totalSupplySum == maxTokens()) {
            return;
        }
        console.log("bound mint value");
        value = bound(value, 1, maxTokens() - totalSupplySum);
        totalSupplySum += value;
        balances[currentActor] += value;
        _mint(currentActor, value);
    }

    function burnTest(uint256 value, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        if (balances[currentActor] == 0) {
            return;
        }
        console.log("bound burn value");
        value = bound(value, 1, balances[currentActor]);
        totalSupplySum -= value;
        balances[currentActor] -= value;
        _burn(currentActor, value);
    }

    function transferTest(uint256 actorTo, uint256 value, uint256 actorIndexSeed) external useActor(actorIndexSeed) {
        console.log("bound 'to' actor ID");
        address to = actors[bound(actorTo, 0, actors.length - 1)];
        if (balances[currentActor] == 0) {
            return;
        }
        console.log("bound transfer value");
        value = bound(value, 1, balances[currentActor]);
        balances[currentActor] -= value;
        balances[to] += value;
        _transfer(currentActor, to, value);
    }
}
