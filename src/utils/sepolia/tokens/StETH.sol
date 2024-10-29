// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit, IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { IStETH } from "../../../interfaces/IStETH.sol";

contract StETH is IStETH, ERC20Burnable, ERC20Permit, Ownable2Step {
    /// @notice The name of the token
    string private constant NAME = "Staked Ether";

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

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool success,) = msg.sender.call{ value: amount }("");
        require(success, "Transfer failed");
    }

    /// @inheritdoc IStETH
    function sweep(address payable to) external onlyOwner {
        (bool success,) = to.call{ value: address(this).balance }("");
        require(success, "Transfer failed");
    }
}
