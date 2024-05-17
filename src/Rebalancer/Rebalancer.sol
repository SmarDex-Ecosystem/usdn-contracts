// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IRebalancer } from "src/interfaces/Rebalancer/IRebalancer.sol";
import { IUsdnProtocol } from "src/interfaces/UsdnProtocol/IUsdnProtocol.sol";

/**
 * @title Rebalancer
 * @notice The goal of this contract is to re-balance the USDN protocol when liquidations reduce the long trading expo
 * It will manage only one position with enough trading expo to re-balance the protocol after liquidations
 * and close/open again with new and existing funds when the imbalance reach a certain threshold
 */
contract Rebalancer is Ownable, IRebalancer {
    using SafeERC20 for IERC20Metadata;

    /// @notice The address of the asset used by the USDN protocol
    IERC20Metadata internal immutable _asset;

    /// @notice The address of the USDN protocol
    IUsdnProtocol internal immutable _usdnProtocol;

    /// @notice The current position version
    uint128 internal _positionVersion;

    /// @notice The version of the last position that got liquidated
    uint128 internal _lastLiquidatedVersion;

    /// @notice The data about the assets deposited in this contract by users
    mapping(address => UserDeposit) internal _userDeposit;

    /// @param usdnProtocol The address of the USDN protocol
    constructor(IUsdnProtocol usdnProtocol) Ownable(msg.sender) {
        _usdnProtocol = usdnProtocol;
        _asset = usdnProtocol.getAsset();
    }

    /// @inheritdoc IRebalancer
    function getUsdnProtocol() external view returns (IUsdnProtocol usdnProtocol_) {
        usdnProtocol_ = _usdnProtocol;
    }

    /// @inheritdoc IRebalancer
    function getPositionVersion() external view returns (uint128 positionVersion_) {
        positionVersion_ = _positionVersion;
    }

    /// @inheritdoc IRebalancer
    function getLastLiquidatedVersion() external view returns (uint128) {
        return _lastLiquidatedVersion;
    }

    /// @inheritdoc IRebalancer
    function getUserDepositData(address user) external view returns (UserDeposit memory userDeposit_) {
        userDeposit_ = _userDeposit[user];
    }

    /// @inheritdoc IRebalancer
    function depositAssets(uint128 amount, address to) external {
        if (to == address(0)) {
            revert RebalancerInvalidAddressTo();
        }

        if (amount == 0) {
            revert RebalancerInvalidAmount();
        }

        uint128 positionVersion = _positionVersion;
        UserDeposit memory depositData = _userDeposit[to];
        if (depositData.amount != 0) {
            if (depositData.entryPositionVersion <= _lastLiquidatedVersion) {
                // if the user was in a position that got liquidated, we should reset its data
                delete depositData;
            } else if (depositData.entryPositionVersion <= positionVersion) {
                // if the user already deposited assets that are in a position, revert
                revert RebalancerUserNotPending();
            }
        }

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        depositData.entryPositionVersion = positionVersion + 1;
        depositData.amount += amount;
        _userDeposit[to] = depositData;

        emit AssetsDeposited(amount, to, positionVersion + 1);
    }

    /// @inheritdoc IRebalancer
    function withdrawPendingAssets(uint128 amount, address to) external {
        if (to == address(0)) {
            revert RebalancerInvalidAddressTo();
        }

        if (amount == 0) {
            revert RebalancerInvalidAmount();
        }

        UserDeposit memory depositData = _userDeposit[msg.sender];
        if (depositData.amount == 0 || depositData.entryPositionVersion <= _positionVersion) {
            revert RebalancerUserNotPending();
        }

        if (depositData.amount < amount) {
            revert RebalancerWithdrawAmountTooLarge();
        }

        // If the amount to withdraw is equal to the deposited funds by this user, delete the mapping entry
        if (amount == depositData.amount) {
            delete _userDeposit[msg.sender];
        }
        // If not, simply subtract the amount withdrawn from the user's balance
        else {
            unchecked {
                _userDeposit[msg.sender].amount -= amount;
            }
        }

        _asset.safeTransfer(to, amount);

        emit PendingAssetsWithdrawn(msg.sender, amount, to);
    }
}
