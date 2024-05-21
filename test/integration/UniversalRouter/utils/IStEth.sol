// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStETH is IERC20Metadata {
    function approve(address _spender, uint256 _amount) external returns (bool);
    function totalSupply() external view returns (uint256);
    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);
    function isStakingPaused() external view returns (bool);
    function transferFrom(address _sender, address _recipient, uint256 _amount) external returns (bool);
    function getEVMScriptExecutor(bytes memory _script) external view returns (address);
    function setStakingLimit(uint256 _maxStakeLimit, uint256 _stakeLimitIncreasePerBlock) external;
    function RESUME_ROLE() external view returns (bytes32);
    function finalizeUpgrade_v2(address _lidoLocator, address _eip712StETH) external;
    function decimals() external pure returns (uint8);
    function getRecoveryVault() external view returns (address);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function getTotalPooledEther() external view returns (uint256);
    function unsafeChangeDepositedValidators(uint256 _newDepositedValidators) external;
    function PAUSE_ROLE() external view returns (bytes32);
    function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool);
    function getTreasury() external view returns (address);
    function isStopped() external view returns (bool);
    function getBufferedEther() external view returns (uint256);
    function initialize(address _lidoLocator, address _eip712StETH) external payable;
    function receiveELRewards() external payable;
    function getWithdrawalCredentials() external view returns (bytes32);
    function getCurrentStakeLimit() external view returns (uint256);
    function getStakeLimitFullInfo()
        external
        view
        returns (
            bool isStakingPaused,
            bool isStakingLimitSet,
            uint256 currentStakeLimit,
            uint256 maxStakeLimit,
            uint256 maxStakeLimitGrowthBlocks,
            uint256 prevStakeLimit,
            uint256 prevStakeBlockNumber
        );
    function transferSharesFrom(address _sender, address _recipient, uint256 _sharesAmount)
        external
        returns (uint256);
    function balanceOf(address _account) external view returns (uint256);
    function resumeStaking() external;
    function getFeeDistribution()
        external
        view
        returns (uint16 treasuryFeeBasisPoints, uint16 insuranceFeeBasisPoints, uint16 operatorsFeeBasisPoints);
    function receiveWithdrawals() external payable;
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);
    function allowRecoverability(address token) external view returns (bool);
    function nonces(address owner) external view returns (uint256);
    function appId() external view returns (bytes32);
    function getOracle() external view returns (address);
    function getContractVersion() external view returns (uint256);
    function getInitializationBlock() external view returns (uint256);
    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256);
    function getEIP712StETH() external view returns (address);
    function transferToVault(address) external;
    function submit(address _referral) external payable returns (uint256);
    function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool);
    function getEVMScriptRegistry() external view returns (address);
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function deposit(uint256 _maxDepositsCount, uint256 _stakingModuleId, bytes memory _depositCalldata) external;
    function UNSAFE_CHANGE_DEPOSITED_VALIDATORS_ROLE() external view returns (bytes32);
    function getBeaconStat()
        external
        view
        returns (uint256 depositedValidators, uint256 beaconValidators, uint256 beaconBalance);
    function removeStakingLimit() external;
    function getFee() external view returns (uint16 totalFee);
    function kernel() external view returns (address);
    function getTotalShares() external view returns (uint256);
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;
    function allowance(address _owner, address _spender) external view returns (uint256);
    function isPetrified() external view returns (bool);
    function getLidoLocator() external view returns (address);
    function canDeposit() external view returns (bool);
    function STAKING_PAUSE_ROLE() external view returns (bytes32);
    function getDepositableEther() external view returns (uint256);
    function sharesOf(address _account) external view returns (uint256);
    function pauseStaking() external;
    function getTotalELRewardsCollected() external view returns (uint256);
}
