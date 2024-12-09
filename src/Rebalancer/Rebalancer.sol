// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ERC165, IERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { UsdnProtocolConstantsLibrary as Constants } from "../UsdnProtocol/libraries/UsdnProtocolConstantsLibrary.sol";
import { IBaseRebalancer } from "../interfaces/Rebalancer/IBaseRebalancer.sol";
import { IRebalancer } from "../interfaces/Rebalancer/IRebalancer.sol";
import { IOwnershipCallback } from "../interfaces/UsdnProtocol/IOwnershipCallback.sol";
import { IUsdnProtocol } from "../interfaces/UsdnProtocol/IUsdnProtocol.sol";
import { IUsdnProtocolTypes as Types } from "../interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";

/**
 * @title Rebalancer
 * @notice The goal of this contract is to re-balance the USDN protocol when liquidations reduce the long trading expo
 * It will manage only one position with enough trading expo to re-balance the protocol after liquidations
 * and close/open again with new and existing funds when the imbalance reaches a certain threshold
 */
contract Rebalancer is Ownable2Step, ReentrancyGuard, ERC165, IOwnershipCallback, IRebalancer, EIP712 {
    using SafeERC20 for IERC20Metadata;
    using SafeCast for uint256;

    /**
     * @dev Structure to hold the transient data during `initiateClosePosition`
     * @param userDepositData The user deposit data
     * @param remainingAssets The remaining rebalancer assets
     * @param positionVersion The current rebalancer position version
     * @param currentPositionData The current rebalancer position data
     * @param amountToCloseWithoutBonus The user amount to close without bonus
     * @param amountToClose The user amount to close including bonus
     * @param protocolPosition The protocol rebalancer position
     * @param user The address of the user that deposited the funds in the rebalancer
     * @param balanceOfAssetBefore The balance of asset before the protocol initiateClosePosition
     * @param balanceOfAssetAfter The balance of asset after the protocol initiateClosePosition
     * @param amount The amount to close relative to the amount deposited
     * @param to The address that will receive the assets
     * @param validator The address that should validate the open position
     * @param userMinPrice The minimum price at which the position can be closed
     * @param deadline The deadline of the close position to be initiated
     * @param closeLockedUntil The timestamp by which a user must wait to perform a {initiateClosePosition}
     */
    struct InitiateCloseData {
        UserDeposit userDepositData;
        uint88 remainingAssets;
        uint256 positionVersion;
        PositionData currentPositionData;
        uint256 amountToCloseWithoutBonus;
        uint256 amountToClose;
        Types.Position protocolPosition;
        address user;
        uint256 balanceOfAssetBefore;
        uint256 balanceOfAssetAfter;
        uint88 amount;
        address to;
        address payable validator;
        uint256 userMinPrice;
        uint256 deadline;
        uint256 closeLockedUntil;
    }

    /// @notice Modifier to check if the caller is the USDN protocol or the owner
    modifier onlyAdmin() {
        if (msg.sender != address(_usdnProtocol) && msg.sender != owner()) {
            revert RebalancerUnauthorized();
        }
        _;
    }

    /// @notice Modifier to check if the caller is the USDN protocol
    modifier onlyProtocol() {
        if (msg.sender != address(_usdnProtocol)) {
            revert RebalancerUnauthorized();
        }
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Constants                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IRebalancer
    uint256 public constant MULTIPLIER_FACTOR = 1e38;

    /// @inheritdoc IRebalancer
    uint256 public constant MAX_ACTION_COOLDOWN = 48 hours;

    /// @inheritdoc IRebalancer
    uint256 public constant MAX_CLOSE_DELAY = 7 days;

    /// @inheritdoc IRebalancer
    bytes32 public constant INITIATE_CLOSE_TYPEHASH = keccak256(
        "InitiateClosePositionDelegation(uint88 amount,address to,uint256 userMinPrice,uint256 deadline,address depositOwner,address depositCloser,uint256 nonce)"
    );

    /* -------------------------------------------------------------------------- */
    /*                                 Immutables                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The address of the asset used by the USDN protocol
    IERC20Metadata internal immutable _asset;

    /// @notice The number of decimals of the asset used by the USDN protocol
    uint256 internal immutable _assetDecimals;

    /// @notice The address of the USDN protocol
    IUsdnProtocol internal immutable _usdnProtocol;

    /* -------------------------------------------------------------------------- */
    /*                                 Parameters                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The maximum leverage that a position can have
    uint256 internal _maxLeverage = 3 * 10 ** Constants.LEVERAGE_DECIMALS;

    /// @notice The minimum amount of assets to be deposited by a user
    uint256 internal _minAssetDeposit;

    /**
     * @notice The timestamp by which a user must wait to perform a {initiateClosePosition}
     * @dev This value will be updated each time a new rebalancer long position is created
     */
    uint256 internal _closeLockedUntil;

    /**
     * @notice The time limits for the initiate/validate process of deposits and withdrawals
     * @dev The user must wait `validationDelay` after the initiate action to perform the corresponding validate
     * action. If the `validationDeadline` has passed, the user is blocked from interacting until the cooldown duration
     * has elapsed (since the moment of the initiate action). After the cooldown, in case of a deposit action, the user
     * must withdraw their funds with `resetDepositAssets`. After the cooldown, in case of a withdrawal action, the user
     * can initiate a new withdrawal again
     */
    TimeLimits internal _timeLimits = TimeLimits({
        validationDelay: 24 seconds,
        validationDeadline: 20 minutes,
        actionCooldown: 4 hours,
        closeDelay: 4 hours
    });

    /* -------------------------------------------------------------------------- */
    /*                                    State                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice The current position version
    uint128 internal _positionVersion;

    /// @notice The amount of assets waiting to be used in the next version of the position
    uint128 internal _pendingAssetsAmount;

    /// @notice The version of the last position that got liquidated
    uint128 internal _lastLiquidatedVersion;

    /// @notice The data about the assets deposited in this contract by users
    mapping(address => UserDeposit) internal _userDeposit;

    /// @notice The data for the specific version of the position
    mapping(uint256 => PositionData) internal _positionData;

    /**
     * @notice The user EIP712 nonce
     * @dev Check {getNonce} in {IRebalancer} for the documentation
     */
    mapping(address => uint256) internal _nonce;

    /// @param usdnProtocol The address of the USDN protocol
    constructor(IUsdnProtocol usdnProtocol) Ownable(msg.sender) EIP712("Rebalancer", "1") {
        _usdnProtocol = usdnProtocol;
        IERC20Metadata asset = usdnProtocol.getAsset();
        _asset = asset;
        _assetDecimals = usdnProtocol.getAssetDecimals();
        _minAssetDeposit = usdnProtocol.getMinLongPosition();

        // set allowance to allow the protocol to pull assets from this contract
        asset.forceApprove(address(usdnProtocol), type(uint256).max);

        // indicate that there are no position for version 0
        _positionData[0].tick = Constants.NO_POSITION_TICK;
    }

    /// @notice To allow this contract to receive ether refunded by the USDN protocol
    receive() external payable onlyProtocol { }

    /// @inheritdoc IRebalancer
    function getAsset() external view returns (IERC20Metadata) {
        return _asset;
    }

    /// @inheritdoc IRebalancer
    function getUsdnProtocol() external view returns (IUsdnProtocol) {
        return _usdnProtocol;
    }

    /// @inheritdoc IRebalancer
    function getPendingAssetsAmount() external view returns (uint128) {
        return _pendingAssetsAmount;
    }

    /// @inheritdoc IRebalancer
    function getPositionVersion() external view returns (uint128) {
        return _positionVersion;
    }

    /// @inheritdoc IRebalancer
    function getPositionMaxLeverage() external view returns (uint256 maxLeverage_) {
        maxLeverage_ = _maxLeverage;
        uint256 protocolMaxLeverage = _usdnProtocol.getMaxLeverage();
        if (protocolMaxLeverage < maxLeverage_) {
            return protocolMaxLeverage;
        }
    }

    /// @inheritdoc IBaseRebalancer
    function getCurrentStateData()
        external
        view
        returns (uint128 pendingAssets_, uint256 maxLeverage_, Types.PositionId memory currentPosId_)
    {
        PositionData storage positionData = _positionData[_positionVersion];
        return (
            _pendingAssetsAmount,
            _maxLeverage,
            Types.PositionId({
                tick: positionData.tick,
                tickVersion: positionData.tickVersion,
                index: positionData.index
            })
        );
    }

    /// @inheritdoc IRebalancer
    function getLastLiquidatedVersion() external view returns (uint128) {
        return _lastLiquidatedVersion;
    }

    /// @inheritdoc IBaseRebalancer
    function getMinAssetDeposit() external view returns (uint256) {
        return _minAssetDeposit;
    }

    /// @inheritdoc IRebalancer
    function getPositionData(uint128 version) external view returns (PositionData memory positionData_) {
        positionData_ = _positionData[version];
    }

    /// @inheritdoc IRebalancer
    function getTimeLimits() external view returns (TimeLimits memory) {
        return _timeLimits;
    }

    /// @inheritdoc IBaseRebalancer
    function getUserDepositData(address user) external view returns (UserDeposit memory) {
        return _userDeposit[user];
    }

    /// @inheritdoc IRebalancer
    function getNonce(address user) external view returns (uint256) {
        return _nonce[user];
    }

    /// @inheritdoc IRebalancer
    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IRebalancer
    function getCloseLockedUntil() external view returns (uint256) {
        return _closeLockedUntil;
    }

    /// @inheritdoc IRebalancer
    function increaseAssetAllowance(uint256 addAllowance) external {
        _asset.safeIncreaseAllowance(address(_usdnProtocol), addAllowance);
    }

    /// @inheritdoc IRebalancer
    function initiateDepositAssets(uint88 amount, address to) external nonReentrant {
        /* authorized previous states:
        - not in rebalancer
            - amount = 0
            - initiateTimestamp = 0
            - entryPositionVersion = 0
        - included in a liquidated position
            - amount > 0
            - 0 < entryPositionVersion <= _lastLiquidatedVersion
            OR
            - positionData.tickVersion != protocol.getTickVersion(positionData.tick)
        */
        if (to == address(0)) {
            revert RebalancerInvalidAddressTo();
        }
        if (amount < _minAssetDeposit) {
            revert RebalancerInsufficientAmount();
        }

        UserDeposit memory depositData = _userDeposit[to];

        // if the user entered the rebalancer before and was not liquidated
        if (depositData.entryPositionVersion > _lastLiquidatedVersion) {
            uint128 positionVersion = _positionVersion;
            PositionData storage positionData = _positionData[positionVersion];
            // if the current position was not liquidated, revert
            if (_usdnProtocol.getTickVersion(positionData.tick) == positionData.tickVersion) {
                revert RebalancerDepositUnauthorized();
            }

            // update the last liquidated version and delete the user data
            _lastLiquidatedVersion = positionVersion;
            delete depositData;
        } else if (depositData.entryPositionVersion > 0) {
            // if the user was in a position that got liquidated, we should reset the deposit data
            delete depositData;
        } else if (depositData.initiateTimestamp > 0 || depositData.amount > 0) {
            // user is already in the rebalancer
            revert RebalancerDepositUnauthorized();
        }

        depositData.amount = amount;
        depositData.initiateTimestamp = uint40(block.timestamp);
        _userDeposit[to] = depositData;

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        emit InitiatedAssetsDeposit(msg.sender, to, amount, block.timestamp);
    }

    /// @inheritdoc IRebalancer
    function validateDepositAssets() external nonReentrant {
        /* authorized previous states:
        - initiated deposit (pending)
            - amount > 0
            - entryPositionVersion == 0
            - initiateTimestamp > 0
            - timestamp is between initiateTimestamp + delay and initiateTimestamp + deadline

        amount is always > 0 if initiateTimestamp > 0
        */
        UserDeposit memory depositData = _userDeposit[msg.sender];

        if (depositData.initiateTimestamp == 0) {
            // user has no action that must be validated
            revert RebalancerNoPendingAction();
        } else if (depositData.entryPositionVersion > 0) {
            revert RebalancerDepositUnauthorized();
        }

        _checkValidationTime(depositData.initiateTimestamp);

        depositData.entryPositionVersion = _positionVersion + 1;
        depositData.initiateTimestamp = 0;
        _userDeposit[msg.sender] = depositData;
        _pendingAssetsAmount += depositData.amount;

        emit AssetsDeposited(msg.sender, depositData.amount, depositData.entryPositionVersion);
    }

    /// @inheritdoc IRebalancer
    function resetDepositAssets() external nonReentrant {
        /* authorized previous states:
        - deposit cooldown elapsed
            - entryPositionVersion == 0
            - initiateTimestamp > 0
            - cooldown elapsed
        */
        UserDeposit memory depositData = _userDeposit[msg.sender];

        if (depositData.initiateTimestamp == 0) {
            // user has not initiated a deposit
            revert RebalancerNoPendingAction();
        } else if (depositData.entryPositionVersion > 0) {
            // user has a withdrawal that must be validated
            revert RebalancerActionNotValidated();
        } else if (block.timestamp < depositData.initiateTimestamp + _timeLimits.actionCooldown) {
            // user must wait until the cooldown has elapsed, then call this function to withdraw the funds
            revert RebalancerActionCooldown();
        }

        // this unblocks the user
        delete _userDeposit[msg.sender];

        _asset.safeTransfer(msg.sender, depositData.amount);

        emit DepositRefunded(msg.sender, depositData.amount);
    }

    /// @inheritdoc IRebalancer
    function initiateWithdrawAssets() external nonReentrant {
        /* authorized previous states:
        - unincluded (pending inclusion)
            - amount > 0
            - entryPositionVersion > _positionVersion
            - initiateTimestamp == 0
        - withdrawal cooldown
            - entryPositionVersion > _positionVersion
            - initiateTimestamp > 0
            - cooldown elapsed

        amount is always > 0 if entryPositionVersion > 0 */

        UserDeposit memory depositData = _userDeposit[msg.sender];

        if (depositData.entryPositionVersion <= _positionVersion) {
            revert RebalancerWithdrawalUnauthorized();
        }
        // entryPositionVersion > _positionVersion

        if (
            depositData.initiateTimestamp > 0
                && block.timestamp < depositData.initiateTimestamp + _timeLimits.actionCooldown
        ) {
            // user must wait until the cooldown has elapsed, then call this function to restart the withdrawal process
            revert RebalancerActionCooldown();
        }
        // initiateTimestamp == 0 or cooldown elapsed

        _userDeposit[msg.sender].initiateTimestamp = uint40(block.timestamp);

        emit InitiatedAssetsWithdrawal(msg.sender);
    }

    /// @inheritdoc IRebalancer
    function validateWithdrawAssets(uint88 amount, address to) external nonReentrant {
        /* authorized previous states:
        - initiated withdrawal
            - initiateTimestamp > 0
            - entryPositionVersion > _positionVersion
            - timestamp is between initiateTimestamp + delay and initiateTimestamp + deadline
        */
        if (to == address(0)) {
            revert RebalancerInvalidAddressTo();
        }
        if (amount == 0) {
            revert RebalancerInvalidAmount();
        }

        UserDeposit memory depositData = _userDeposit[msg.sender];

        if (depositData.entryPositionVersion <= _positionVersion) {
            revert RebalancerWithdrawalUnauthorized();
        }
        if (depositData.initiateTimestamp == 0) {
            revert RebalancerNoPendingAction();
        }
        _checkValidationTime(depositData.initiateTimestamp);

        if (amount > depositData.amount) {
            revert RebalancerInvalidAmount();
        }

        // update deposit data
        if (depositData.amount == amount) {
            // we withdraw the full amount, delete the mapping entry
            delete _userDeposit[msg.sender];
        } else {
            // partial withdrawal
            unchecked {
                // checked above: amount is strictly smaller than depositData.amount
                depositData.amount -= amount;
            }
            // the remaining amount must at least be _minAssetDeposit
            if (depositData.amount < _minAssetDeposit) {
                revert RebalancerInsufficientAmount();
            }
            depositData.initiateTimestamp = 0;
            _userDeposit[msg.sender] = depositData;
        }

        // update global state
        _pendingAssetsAmount -= amount;

        _asset.safeTransfer(to, amount);

        emit AssetsWithdrawn(msg.sender, to, amount);
    }

    /// @inheritdoc IRebalancer
    function initiateClosePosition(
        uint88 amount,
        address to,
        address payable validator,
        uint256 userMinPrice,
        uint256 deadline,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData,
        bytes calldata delegationData
    ) external payable nonReentrant returns (Types.LongActionOutcome outcome_) {
        InitiateCloseData memory data;
        data.amount = amount;
        data.to = to;
        data.validator = validator;
        data.userMinPrice = userMinPrice;
        data.deadline = deadline;
        data.closeLockedUntil = _closeLockedUntil;

        return _initiateClosePosition(data, currentPriceData, previousActionsData, delegationData);
    }

    /**
     * @notice Refunds any ether in this contract to the caller
     * @dev This contract should not hold any ether so any sent to it belongs to the current caller
     */
    function _refundEther() internal {
        uint256 amount = address(this).balance;
        if (amount > 0) {
            // slither-disable-next-line arbitrary-send-eth
            (bool success,) = msg.sender.call{ value: amount }("");
            if (!success) {
                revert RebalancerEtherRefundFailed();
            }
        }
    }

    /// @inheritdoc IBaseRebalancer
    function updatePosition(Types.PositionId calldata newPosId, uint128 previousPosValue)
        external
        onlyProtocol
        nonReentrant
    {
        uint128 positionVersion = _positionVersion;
        PositionData memory previousPositionData = _positionData[positionVersion];
        // set the multiplier accumulator to 1 by default
        uint256 accMultiplier = MULTIPLIER_FACTOR;

        // if the current position version exists
        if (previousPositionData.amount > 0) {
            // if the position has not been liquidated
            if (previousPosValue > 0) {
                // update the multiplier accumulator
                accMultiplier = FixedPointMathLib.fullMulDiv(
                    previousPosValue, previousPositionData.entryAccMultiplier, previousPositionData.amount
                );
            } else if (_lastLiquidatedVersion != positionVersion) {
                // update the last liquidated version tracker
                _lastLiquidatedVersion = positionVersion;
            }
        }

        // update the position's version
        ++positionVersion;
        _positionVersion = positionVersion;

        uint128 positionAmount = _pendingAssetsAmount + previousPosValue;
        if (newPosId.tick != Constants.NO_POSITION_TICK) {
            _positionData[positionVersion] = PositionData({
                entryAccMultiplier: accMultiplier,
                tickVersion: newPosId.tickVersion,
                index: newPosId.index,
                amount: positionAmount,
                tick: newPosId.tick
            });

            // Reset the pending assets amount as they are all used in the new position
            _pendingAssetsAmount = 0;
            _closeLockedUntil = block.timestamp + _timeLimits.closeDelay;
        } else {
            _positionData[positionVersion].tick = Constants.NO_POSITION_TICK;
        }

        emit PositionVersionUpdated(positionVersion, accMultiplier, positionAmount, newPosId);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IRebalancer
    function setPositionMaxLeverage(uint256 newMaxLeverage) external onlyOwner {
        if (newMaxLeverage > _usdnProtocol.getMaxLeverage()) {
            revert RebalancerInvalidMaxLeverage();
        } else if (newMaxLeverage <= Constants.REBALANCER_MIN_LEVERAGE) {
            revert RebalancerInvalidMaxLeverage();
        }

        _maxLeverage = newMaxLeverage;

        emit PositionMaxLeverageUpdated(newMaxLeverage);
    }

    /// @inheritdoc IBaseRebalancer
    function setMinAssetDeposit(uint256 minAssetDeposit) external onlyAdmin {
        if (_usdnProtocol.getMinLongPosition() > minAssetDeposit) {
            revert RebalancerInvalidMinAssetDeposit();
        }

        _minAssetDeposit = minAssetDeposit;
        emit MinAssetDepositUpdated(minAssetDeposit);
    }

    /// @inheritdoc IRebalancer
    function setTimeLimits(uint64 validationDelay, uint64 validationDeadline, uint64 actionCooldown, uint64 closeDelay)
        external
        onlyOwner
    {
        if (validationDelay >= validationDeadline) {
            revert RebalancerInvalidTimeLimits();
        }
        if (validationDeadline < validationDelay + 1 minutes) {
            revert RebalancerInvalidTimeLimits();
        }
        if (actionCooldown < validationDeadline) {
            revert RebalancerInvalidTimeLimits();
        }
        if (actionCooldown > MAX_ACTION_COOLDOWN) {
            revert RebalancerInvalidTimeLimits();
        }
        if (closeDelay > MAX_CLOSE_DELAY) {
            revert RebalancerInvalidTimeLimits();
        }

        _timeLimits = TimeLimits({
            validationDelay: validationDelay,
            validationDeadline: validationDeadline,
            actionCooldown: actionCooldown,
            closeDelay: closeDelay
        });

        emit TimeLimitsUpdated(validationDelay, validationDeadline, actionCooldown, closeDelay);
    }

    /// @inheritdoc IOwnershipCallback
    function ownershipCallback(address, Types.PositionId calldata) external pure {
        revert RebalancerUnauthorized(); // first version of the rebalancer contract so we are always reverting
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        if (interfaceId == type(IOwnershipCallback).interfaceId) {
            return true;
        }
        if (interfaceId == type(IRebalancer).interfaceId) {
            return true;
        }
        if (interfaceId == type(IBaseRebalancer).interfaceId) {
            return true;
        }

        return super.supportsInterface(interfaceId);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Internal functions                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Check if the validate action happens between the validation delay and the validation deadline
     * @dev If the block timestamp is before initiateTimestamp + validationDelay, the function will revert
     * If the block timestamp is after initiateTimestamp + validationDeadline, the function will revert
     * @param initiateTimestamp The timestamp of the initiate action
     */
    function _checkValidationTime(uint40 initiateTimestamp) internal view {
        TimeLimits memory timeLimits = _timeLimits;
        if (block.timestamp < initiateTimestamp + timeLimits.validationDelay) {
            // user must wait until the delay has elapsed
            revert RebalancerValidateTooEarly();
        }
        if (block.timestamp > initiateTimestamp + timeLimits.validationDeadline) {
            // user must wait until the cooldown has elapsed, then call `resetDepositAssets` to withdraw the funds
            revert RebalancerActionCooldown();
        }
    }

    /**
     * @notice Performs the {initiateClosePosition} EIP712 delegation signature verification
     * @dev Reverts if the function arguments don't match those included in the signature
     * and if the signer isn't the owner of the deposit
     * @param delegationData The delegation data that should include the depositOwner and the delegation signature
     * @param amount The amount to close relative to the amount deposited
     * @param to The address that will receive the assets
     * @param userMinPrice The minimum price at which the position can be closed
     * @param deadline The deadline of the close position to be initiated
     * @return depositOwner_ The owner of the rebalancer deposit position
     */
    function _verifyInitiateCloseDelegation(
        uint88 amount,
        address to,
        uint256 userMinPrice,
        uint256 deadline,
        bytes calldata delegationData
    ) internal returns (address depositOwner_) {
        bytes memory signature;
        (depositOwner_, signature) = abi.decode(delegationData, (address, bytes));

        uint256 nonce = _nonce[depositOwner_];

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    INITIATE_CLOSE_TYPEHASH, amount, to, userMinPrice, deadline, depositOwner_, msg.sender, nonce
                )
            )
        );

        if (ECDSA.recover(digest, signature) != depositOwner_) {
            revert RebalancerInvalidDelegationSignature();
        }

        _nonce[depositOwner_] = nonce + 1;
    }

    /**
     * @notice Closes a user deposited amount of the current UsdnProtocol rebalancer position
     * @param data The structure to hold the transient data during {initiateClosePosition}
     * @param currentPriceData The current price data (used to calculate the temporary leverage and entry price,
     * pending validation)
     * @param previousActionsData The data needed to validate actionable pending actions
     * @param delegationData An optional delegation data that include the depositOwner and an EIP712 signature to
     * provide when closing a position on the owner's behalf
     * @return outcome_ The outcome of the `initiateClosePosition` call to the USDN protocol
     */
    function _initiateClosePosition(
        InitiateCloseData memory data,
        bytes calldata currentPriceData,
        Types.PreviousActionsData calldata previousActionsData,
        bytes calldata delegationData
    ) internal returns (Types.LongActionOutcome outcome_) {
        if (block.timestamp < data.closeLockedUntil) {
            revert RebalancerCloseLockedUntil(data.closeLockedUntil);
        }
        if (data.amount == 0) {
            revert RebalancerInvalidAmount();
        }
        if (delegationData.length == 0) {
            data.user = msg.sender;
        } else {
            data.user =
                _verifyInitiateCloseDelegation(data.amount, data.to, data.userMinPrice, data.deadline, delegationData);
        }

        data.userDepositData = _userDeposit[data.user];

        if (data.amount > data.userDepositData.amount) {
            revert RebalancerInvalidAmount();
        }

        data.remainingAssets = data.userDepositData.amount - data.amount;
        if (data.remainingAssets > 0 && data.remainingAssets < _minAssetDeposit) {
            revert RebalancerInvalidAmount();
        }

        if (data.userDepositData.entryPositionVersion == 0) {
            revert RebalancerUserPending();
        }

        if (data.userDepositData.entryPositionVersion <= _lastLiquidatedVersion) {
            revert RebalancerUserLiquidated();
        }

        data.positionVersion = _positionVersion;

        if (data.userDepositData.entryPositionVersion > data.positionVersion) {
            revert RebalancerUserPending();
        }

        data.currentPositionData = _positionData[data.positionVersion];

        data.amountToCloseWithoutBonus = FixedPointMathLib.fullMulDiv(
            data.amount,
            data.currentPositionData.entryAccMultiplier,
            _positionData[data.userDepositData.entryPositionVersion].entryAccMultiplier
        );

        (data.protocolPosition,) = _usdnProtocol.getLongPosition(
            Types.PositionId({
                tick: data.currentPositionData.tick,
                tickVersion: data.currentPositionData.tickVersion,
                index: data.currentPositionData.index
            })
        );

        // include bonus
        data.amountToClose = data.amountToCloseWithoutBonus
            + data.amountToCloseWithoutBonus * (data.protocolPosition.amount - data.currentPositionData.amount)
                / data.currentPositionData.amount;

        data.balanceOfAssetBefore = _asset.balanceOf(address(this));

        // slither-disable-next-line reentrancy-eth
        outcome_ = _usdnProtocol.initiateClosePosition{ value: msg.value }(
            Types.PositionId({
                tick: data.currentPositionData.tick,
                tickVersion: data.currentPositionData.tickVersion,
                index: data.currentPositionData.index
            }),
            data.amountToClose.toUint128(),
            data.userMinPrice,
            data.to,
            data.validator,
            data.deadline,
            currentPriceData,
            previousActionsData,
            ""
        );
        data.balanceOfAssetAfter = _asset.balanceOf(address(this));

        if (outcome_ == Types.LongActionOutcome.Processed) {
            if (data.remainingAssets == 0) {
                delete _userDeposit[data.user];
            } else {
                _userDeposit[data.user].amount = data.remainingAssets;
            }

            // safe cast is already made on amountToClose
            data.currentPositionData.amount -= uint128(data.amountToCloseWithoutBonus);

            if (data.currentPositionData.amount == 0) {
                PositionData memory newPositionData;
                newPositionData.tick = Constants.NO_POSITION_TICK;
                _positionData[data.positionVersion] = newPositionData;
            } else {
                _positionData[data.positionVersion].amount = data.currentPositionData.amount;
            }

            emit ClosePositionInitiated(data.user, data.amount, data.amountToClose, data.remainingAssets);
        }

        // If the rebalancer received assets, it means it was rewarded for liquidating positions
        // So we need to forward those rewards to the msg.sender
        if (data.balanceOfAssetAfter > data.balanceOfAssetBefore) {
            _asset.safeTransfer(msg.sender, data.balanceOfAssetAfter - data.balanceOfAssetBefore);
        }

        // sent back any ether left in the contract
        _refundEther();
    }
}
