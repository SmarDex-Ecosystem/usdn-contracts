// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit, IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IStETH } from "../interfaces/IStETH.sol";
import { IWstETH } from "../interfaces/IWstETH.sol";

contract MockStETH is IStETH, ERC20Burnable, ERC20Permit, Ownable {
    /// @notice The name of the token
    string private constant NAME = "Mock Staked Ether";

    /// @notice The symbol of the token
    string private constant SYMBOL = "stETH";

    constructor() ERC20(NAME, SYMBOL) ERC20Permit(NAME) Ownable(msg.sender) { }

    receive() external payable {
        if (msg.value != 0) {
            _mint(msg.sender, msg.value);
        }
    }

    /**
     * @inheritdoc IERC20Permit
     * @dev This function must be overridden to fix a solidity compiler error
     */
    function nonces(address owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }

    /**
     * @inheritdoc IStETH
     * @dev Returns the amount of ether of the contract. As the Mock contract can mint without ether, this function
     * might return a different amount than totalSupply()
     */
    function getTotalPooledEther() external view override returns (uint256) {
        return address(this).balance;
    }

    /// @inheritdoc IStETH
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /// @inheritdoc IStETH
    function submit(address account) external payable {
        if (msg.value != 0) {
            _mint(account, msg.value);
        }
    }

    /// @inheritdoc IStETH
    function sweep(address payable to) external onlyOwner {
        (bool success,) = to.call{ value: address(this).balance }("");
        require(success, "Transfer failed");
    }

    /// @inheritdoc IStETH
    function setStEthPerToken(uint256 stEthAmount, IWstETH wstETH) external onlyOwner returns (uint256) {
        // assuming _decimalOffset is 0 on the wstETH vault
        uint256 newTotalAsset = Math.mulDiv(stEthAmount, wstETH.totalSupply() + 1, 1 ether) - 1;
        uint256 balanceWstETH = balanceOf(address(wstETH));

        if (newTotalAsset > balanceWstETH) {
            _mint(address(wstETH), newTotalAsset - balanceWstETH);
        } else {
            _burn(address(wstETH), balanceWstETH - newTotalAsset);
        }

        return wstETH.stEthPerToken();
    }
}
