// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Usdn } from "../../../src/Usdn/Usdn.sol";

import { Test } from "forge-std/Test.sol";

import "../../utils/Constants.sol";
import { UsdnrHandler } from "./utils/Handler.sol";

contract TestUsdnrInvariants is Test {
    Usdn internal _usdn;
    UsdnrHandler internal _usdnr;
    address[] internal _actors = [USER_1, USER_2, USER_3, USER_4];

    function setUp() public {
        _usdn = new Usdn(address(this), address(this));
        _usdnr = new UsdnrHandler(_usdn, address(this), _actors);
        _usdn.grantRole(_usdn.REBASER_ROLE(), address(_usdnr));
        _usdn.grantRole(_usdn.MINTER_ROLE(), address(_usdnr));

        for (uint256 i = 0; i < _actors.length; i++) {
            _usdn.mint(_actors[i], 1_000_000 ether);

            vm.startPrank(_actors[i]);
            _usdn.approve(address(_usdnr), type(uint256).max);
            _usdnr.approve(address(_usdnr), type(uint256).max);
            vm.stopPrank();
        }

        targetContract(address(_usdnr));

        bytes4[] memory usdnrSelectors = new bytes4[](7);
        usdnrSelectors[0] = _usdnr.wrapTest.selector;
        usdnrSelectors[1] = _usdnr.wrapSharesTest.selector;
        usdnrSelectors[2] = _usdnr.unwrapTest.selector;
        usdnrSelectors[3] = _usdnr.withdrawYieldTest.selector;
        usdnrSelectors[4] = _usdnr.mintUsdn.selector;
        usdnrSelectors[5] = _usdnr.rebaseTest.selector;
        usdnrSelectors[6] = _usdnr.giftUsdn.selector;
        targetSelector(FuzzSelector({ addr: address(_usdnr), selectors: usdnrSelectors }));
    }

    function invariant_job1() public view {
        assertInvariants();
    }

    function invariant_job2() public view {
        assertInvariants();
    }

    function invariant_job3() public view {
        assertInvariants();
    }

    function invariant_job4() public view {
        assertInvariants();
    }

    function assertInvariants() internal view {
        uint256 totalSupply = _usdnr.totalSupply();
        uint256 totalUsdnInContract = _usdn.balanceOf(address(_usdnr));

        // total shares of USDN held by USDNr should always be greater than or equal to total supply of USDNr
        if (totalUsdnInContract < totalSupply) {
            // account for rounding to the nearest of USDN shares
            assertApproxEqAbs(
                totalUsdnInContract, totalSupply, 1, "USDN balance in USDNr >= total supply with rounding"
            );
        }
    }

    function afterInvariant() public {
        _usdnr.withdrawYieldTest();

        for (uint256 i = 0; i < _actors.length; i++) {
            uint256 balanceOf = _usdnr.balanceOf(_actors[i]);

            if (balanceOf != 0) {
                vm.prank(_actors[i]);
                _usdnr.unwrap(balanceOf, _actors[i]);
            }
        }

        assertEq(_usdnr.totalSupply(), 0, "total supply after full unwrap should be 0");
        assertApproxEqAbs(_usdn.balanceOf(address(_usdnr)), 0, 1, "total USDN in USDNr after should be 0");
    }
}
