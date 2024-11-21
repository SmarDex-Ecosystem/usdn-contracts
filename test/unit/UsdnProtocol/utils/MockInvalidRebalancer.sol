// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

contract MockInvalidRebalancer {
    uint256 internal _minAssetDeposit;

    function getMinAssetDeposit() external view returns (uint256) {
        return _minAssetDeposit;
    }

    function setMinAssetDeposit(uint256 minAssetDeposit) external {
        _minAssetDeposit = minAssetDeposit;
    }

    receive() external payable { }
}
