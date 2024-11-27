// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract UsdnProtocolMock {
    IERC20Metadata _asset;
    mapping(int24 => uint256) _tickToTickVersion;

    constructor(IERC20Metadata asset) {
        _asset = asset;
    }

    function getAsset() external view returns (IERC20Metadata) {
        return _asset;
    }

    function getAssetDecimals() external view returns (uint256) {
        return _asset.decimals();
    }

    function getMinLongPosition() external pure returns (uint256) {
        return 2 ether;
    }

    function getTickVersion(int24 tick) external view returns (uint256) {
        return _tickToTickVersion[tick];
    }

    function setTickVersion(int24 tick, uint256 tickVersion) external {
        _tickToTickVersion[tick] = tickVersion;
    }
}
