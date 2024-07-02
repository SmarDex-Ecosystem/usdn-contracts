// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

contract Weth {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    error InsufficientBalance();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    receive() external payable {
        _deposit();
    }

    function _deposit() internal {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function deposit() external payable {
        _deposit();
    }

    function mint(address account, uint256 amount) public {
        balanceOf[account] += amount;
    }

    function withdraw(uint256 wad) external {
        if (balanceOf[msg.sender] < wad) {
            revert InsufficientBalance();
        }
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        if (balanceOf[src] < wad) {
            revert InsufficientBalance();
        }

        if (src != msg.sender && allowance[src][msg.sender] != type(uint128).max) {
            if (allowance[src][msg.sender] < wad) {
                revert InsufficientBalance();
            }
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}
