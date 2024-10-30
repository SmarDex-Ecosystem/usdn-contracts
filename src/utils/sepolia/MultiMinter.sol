// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { Sdex } from "./tokens/Sdex.sol";
import { StETH } from "./tokens/StETH.sol";
import { WstETH } from "./tokens/WstETH.sol";

interface IOwnable {
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
}

interface IMultiMinter {
    struct Call {
        address target;
        bytes callData;
    }

    function mint(address to, uint256 amountSDEX, uint256 amountSTETH, uint256 amountWSTETH) external;

    function setStEthPerWstEth(uint256 stEthAmount) external;

    function transferOwnershipOf(address contractAdr, address newOwner) external;

    function acceptOwnershipOf(address contractAdr) external;

    function sweep(address payable to) external;

    function aggregateOnlyOwner(Call[] calldata calls) external payable returns (bytes[] memory returnData);
}

/**
 * @title MultiMinter
 * @notice Contract to mint SDEX, STETH and WSTETH tokens
 * This contract must have the owner of SDEX and WstETH tokens
 */
contract MultiMinter is IMultiMinter, Ownable2Step {
    Sdex immutable SDEX;
    StETH immutable STETH;
    WstETH immutable WSTETH;

    constructor(Sdex sdex, StETH stETH, WstETH wstETH) Ownable(msg.sender) {
        SDEX = sdex;
        STETH = stETH;
        WSTETH = wstETH;
    }

    function mint(address to, uint256 amountSDEX, uint256 amountSTETH, uint256 amountWSTETH) public onlyOwner {
        if (amountSDEX != 0) {
            SDEX.mint(to, amountSDEX);
        }

        if (amountWSTETH != 0) {
            uint256 stethAmount = WSTETH.getStETHByWstETH(amountWSTETH);
            STETH.mint(address(this), stethAmount);
            STETH.approve(address(WSTETH), stethAmount);
            WSTETH.wrap(stethAmount);
            WSTETH.transfer(to, WSTETH.balanceOf(address(this)));
        }

        if (amountSTETH != 0) {
            STETH.mint(to, amountSTETH);
        }
    }

    function setStEthPerWstEth(uint256 stEthAmount) external onlyOwner {
        require(stEthAmount > 0, "Cannot be 0");

        WSTETH.setStEthPerToken(stEthAmount);
    }

    function transferOwnershipOf(address contractAdr, address newOwner) external onlyOwner {
        IOwnable(contractAdr).transferOwnership(newOwner);
    }

    function acceptOwnershipOf(address contractAdr) external onlyOwner {
        IOwnable(contractAdr).acceptOwnership();
    }

    function sweep(address payable to) external onlyOwner {
        STETH.sweep(to);
        WSTETH.sweep(to);
        (bool success,) = to.call{ value: address(this).balance }("");
        require(success, "Error while sending Ether");
    }

    /**
     * @notice Aggregate multiple calls in one transaction
     * @param calls The calls to aggregate
     * @return returnData The return data of each call
     */
    function aggregateOnlyOwner(Call[] calldata calls) external payable onlyOwner returns (bytes[] memory returnData) {
        uint256 length = calls.length;
        returnData = new bytes[](length);
        Call calldata call;
        for (uint256 i = 0; i < length;) {
            bool success;
            call = calls[i];
            (success, returnData[i]) = call.target.call(call.callData);
            require(success, "Multicall3: call failed");
            unchecked {
                ++i;
            }
        }
    }
}
