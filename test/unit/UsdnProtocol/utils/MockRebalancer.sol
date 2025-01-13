// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { UsdnProtocolConstantsLibrary as Constants } from
    "../../../../src/UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IBaseRebalancer } from "../../../../src/interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancerTypes } from "../../../../src/interfaces/Rebalancer/IRebalancerTypes.sol";
import { IUsdnProtocolTypes as Types } from "../../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

contract MockRebalancer is IBaseRebalancer, IRebalancerTypes {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;

    uint256 public constant MULTIPLIER_FACTOR = 1e38;

    uint256 internal _minAssetDeposit;
    uint128 internal _pendingAssets;
    uint256 internal _maxLeverage;
    uint128 internal _positionVersion;
    uint128 internal _pendingAssetsAmount;
    uint128 internal _lastLiquidatedVersion;
    mapping(address => UserDeposit) internal _userDeposit;
    mapping(uint256 => PositionData) internal _positionData;

    constructor() {
        // indicate that there are no position for version 0
        _positionData[0].tick = Constants.NO_POSITION_TICK;
    }

    function setCurrentStateData(uint128 pendingAssets, uint256 maxLeverage, Types.PositionId memory currentPosId)
        external
    {
        _pendingAssets = pendingAssets;
        _maxLeverage = maxLeverage;
        _positionData[_positionVersion].tick = currentPosId.tick;
        _positionData[_positionVersion].tickVersion = currentPosId.tickVersion;
        _positionData[_positionVersion].index = currentPosId.index;
    }

    function getCurrentStateData()
        external
        view
        returns (uint128, uint256, uint128, uint256, Types.PositionId memory)
    {
        return (
            _pendingAssets,
            _maxLeverage,
            _positionData[_positionVersion].amount,
            _positionData[_positionVersion].entryAccMultiplier,
            Types.PositionId(
                _positionData[_positionVersion].tick,
                _positionData[_positionVersion].tickVersion,
                _positionData[_positionVersion].index
            )
        );
    }

    function setUserDepositData(address user, UserDeposit memory userDeposit) external {
        _userDeposit[user] = userDeposit;
    }

    function getUserDepositData(address user) external view returns (UserDeposit memory) {
        return _userDeposit[user];
    }

    function updatePosition(Types.PositionId calldata newPosId, uint128 previousPositionValue) external {
        ++_positionVersion;
        _positionData[_positionVersion].tick = newPosId.tick;
        _positionData[_positionVersion].tickVersion = newPosId.tickVersion;
        _positionData[_positionVersion].index = newPosId.index;
        _positionData[_positionVersion].amount = _pendingAssets + previousPositionValue;
        _positionData[_positionVersion].entryAccMultiplier = MULTIPLIER_FACTOR;

        _pendingAssets = 0;
    }

    function getMinAssetDeposit() external view returns (uint256) {
        return _minAssetDeposit;
    }

    function setMinAssetDeposit(uint256 minAssetDeposit) external {
        _minAssetDeposit = minAssetDeposit;
    }

    function getPositionVersion() external view returns (uint128) {
        return _positionVersion;
    }
}
