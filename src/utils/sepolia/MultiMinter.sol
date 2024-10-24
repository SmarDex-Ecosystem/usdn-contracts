// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IStETH } from "../../interfaces/IStETH.sol";
import { IWstETH } from "../../interfaces/IWstETH.sol";

interface IMintable {
    function mint(address, uint256) external;
}

interface IOwnable {
    function transferOwnership(address newOwner) external;
    function acceptOwnership() external;
}

interface IMultiMinter {
    struct Call {
        address target;
        bytes callData;
    }

    function mint(address adrs, uint256 amountSDEX, uint256 amountWSTETH, uint256 amountSTETH) external;

    function mint(address adrs, uint256 amountSDEX, uint256 amountWSTETH, uint256 amountSTETH, uint256 amountETH)
        external
        payable;

    function setStEthPerToken(uint256 stEthAmount, IWstETH wstETH) external;

    function transferOwnershipOf(address contractAdr, address newOwner) external;

    function acceptOwnershipOf(address contractAdr) external;

    function sweep(address to) external;

    function aggregateOnlyOwner(Call[] calldata calls)
        external
        payable
        returns (uint256 blockNumber, bytes[] memory returnData);
}

/**
 * @title MultiMinter
 * @notice Contract to mint SDEX and WstETH tokens
 * This contract must have the owner of SDEX and WstETH tokens
 */
contract MultiMinter is IMultiMinter, Ownable2Step {
    IMintable immutable SDEX;
    IStETH immutable STETH;
    IWstETH immutable WSTETH;

    constructor(address sdex, address steth, address wsteth) Ownable(msg.sender) {
        SDEX = IMintable(sdex);
        STETH = IStETH(steth);
        WSTETH = IWstETH(wsteth);
    }

    function mint(address to, uint256 amountSDEX, uint256 amountWSTETH, uint256 amountSTETH) external onlyOwner {
        mint(to, amountSDEX, amountWSTETH, amountSTETH, 0);
    }

    function mint(address to, uint256 amountSDEX, uint256 amountWSTETH, uint256 amountSTETH, uint256 amountETH)
        public
        payable
        onlyOwner
    {
        if (amountSDEX != 0) {
            SDEX.mint(to, amountSDEX);
        }

        if (amountWSTETH != 0) {
            uint256 stethAmount = WSTETH.getStETHByWstETH(amountWSTETH);
            STETH.mint(address(this), stethAmount);
            WSTETH.wrap(stethAmount);
            WSTETH.transfer(to, WSTETH.balanceOf(address(this)));
        }

        if (amountSTETH != 0) {
            STETH.mint(to, amountSTETH);
        }

        if (amountETH != 0) {
            (bool success,) = to.call{ value: amountETH }("");
            require(success, "Error while sending Ether");
        }
    }

    function setStEthPerToken(uint256 stEthAmount, IWstETH wstETH) external onlyOwner {
        STETH.setStEthPerToken(stEthAmount, wstETH);
    }

    function transferOwnershipOf(address contractAdr, address newOwner) external onlyOwner {
        IOwnable(contractAdr).transferOwnership(newOwner);
    }

    function acceptOwnershipOf(address contractAdr) external onlyOwner {
        IOwnable(contractAdr).acceptOwnership();
    }

    function sweep(address to) external onlyOwner {
        (bool success,) = to.call{ value: address(this).balance }("");
        require(success, "Error while sending Ether");
    }

    /**
     * @notice Aggregate multiple calls in one transaction
     * @param calls The calls to aggregate
     * @return blockNumber The block number of the call
     * @return returnData The return data of each call
     */
    function aggregateOnlyOwner(Call[] calldata calls)
        external
        payable
        onlyOwner
        returns (uint256 blockNumber, bytes[] memory returnData)
    {
        blockNumber = block.number;
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
