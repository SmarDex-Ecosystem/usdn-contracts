// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IStETH } from "../interfaces/IStEth.sol";
import { IWstETH } from "../interfaces/IWstETH.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { ERC20Permit, IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract StETH is IStETH, ERC20Burnable, ERC20Permit, Ownable {
    string private constant NAME = "Mock Staked Ether";
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
    function nonces(address _owner) public view override(IERC20Permit, ERC20Permit) returns (uint256) {
        return super.nonces(_owner);
    }

    /// @inheritdoc IStETH
    function mint(address account, uint256 amount) external onlyOwner {
        _mint(account, amount);
    }

    /// @inheritdoc IStETH
    function deposit(address account) external payable {
        if (msg.value != 0) {
            _mint(account, msg.value);
        }
    }

    /// @inheritdoc IStETH
    function sweep(address to) external onlyOwner {
        (bool success,) = to.call{ value: address(this).balance }("");
        require(success, "Transfer failed");
    }

    /// @inheritdoc IStETH
    function setStEthPerToken(uint256 _stEthAmount, IWstETH wstETH) external onlyOwner returns (uint256) {
        if (wstETH.stEthPerToken() > _stEthAmount) {
            revert setStEthPerTokenTooSmall(wstETH.stEthPerToken(), _stEthAmount);
        }

        // assuming _decimalOffset is 0 on the wstETH vault
        uint256 newTotalAsset = Math.mulDiv(_stEthAmount, wstETH.totalSupply() + 1, 1 ether) - 1;
        _mint(address(wstETH), newTotalAsset - balanceOf(address(wstETH)));

        return wstETH.stEthPerToken();
    }
}
