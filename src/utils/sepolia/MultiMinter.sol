// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

interface IMintable {
    function mint(address, uint256) external;
}

interface IWstETH is IMintable {
    function setStEthPerToken(uint256 stEthAmount) external;
}

interface IOwnable {
    function transferOwnership(address newOwner) external;
}

interface IMultiMinter {
    struct Call {
        address target;
        bytes callData;
    }

    function mint(address adrs, uint256 amountSDEX, uint256 amountWSTETH) external;

    function mint(address adrs, uint256 amountSDEX, uint256 amountWSTETH, uint256 amountETH) external payable;

    function setStEthPerToken(uint256 stEthAmount) external;

    function transferOwnershipOf(IOwnable contractAdr, address newOwner) external;

    function sweep(address to) external;

    function aggregateOnlyOwner(Call[] calldata calls)
        external
        payable
        returns (uint256 blockNumber, bytes[] memory returnData);
}

contract MultiMinter is IMultiMinter, Ownable2Step {
    IMintable immutable SDEX;
    IWstETH immutable WSTETH;

    constructor(address sdex, address wsteth) Ownable(msg.sender) {
        SDEX = IMintable(sdex);
        WSTETH = IWstETH(wsteth);
    }

    function mint(address to, uint256 amountSDEX, uint256 amountWSTETH) external onlyOwner {
        mint(to, amountSDEX, amountWSTETH, 0);
    }

    function mint(address to, uint256 amountSDEX, uint256 amountWSTETH, uint256 amountETH) public payable onlyOwner {
        if (amountSDEX != 0) {
            SDEX.mint(to, amountSDEX);
        }

        if (amountWSTETH != 0) {
            WSTETH.mint(to, amountWSTETH);
        }

        if (amountETH != 0) {
            (bool success,) = to.call{ value: amountETH }("");
            require(success, "Error while sending Ether");
        }
    }

    function setStEthPerToken(uint256 stEthAmount) external onlyOwner {
        WSTETH.setStEthPerToken(stEthAmount);
    }

    function transferOwnershipOf(IOwnable contractAdr, address newOwner) external onlyOwner {
        contractAdr.transferOwnership(newOwner);
    }

    function sweep(address to) external onlyOwner {
        (bool success,) = to.call{ value: address(this).balance }("");
        require(success, "Error while sending Ether");
    }

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
