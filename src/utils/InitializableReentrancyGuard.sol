// SPDX-License-Identifier: MIT
// based on the OpenZeppelin implementation

pragma solidity 0.8.26;

/**
 * @title InitializableReentrancyGuard
 * @dev Contract module that helps prevent reentrant calls to a function and ensures the initializer has been called
 */
abstract contract InitializableReentrancyGuard {
    // booleans are more expensive than uint256 or any type that takes up a full word because each write operation emits
    // an extra SLOAD to first read the slot's contents, replace the bits taken up by the boolean and then write back.
    // This is the compiler's defense against contract upgrades and pointer aliasing, and it cannot be disabled

    /// @notice The uninitialized state of the contract
    uint256 private constant UNINITIALIZED = 0;
    /// @notice The initialized state of the contract
    uint256 private constant INITIALIZED = 1;

    /**
     * @custom:storage-location erc7201:InitializableReentrancyGuard.storage.status
     * @notice The storage structure of the contract
     * @param _status The state of the contract
     */
    struct StorageStatus {
        /// @notice The state of the contract
        uint256 _status;
    }

    /**
     * @notice The storage slot of the {StorageStatus} struct
     * @dev keccak256(abi.encode(uint256(keccak256("InitializableReentrancyGuard.storage.status")) - 1)) &
     * ~bytes32(uint256(0xff));
     */
    bytes32 private constant STORAGE_SLOT_STATUS = 0x6f33a3bc64034eea47937f56d5e165f09a61a6a995142939d6f3e40f101ea600;

    /**
     * @notice Get the struct pointer of the contract storage
     * @return s_ The pointer to the struct
     */
    function _getStorageStatus() internal pure returns (StorageStatus storage s_) {
        assembly {
            s_.slot := STORAGE_SLOT_STATUS
        }
    }

    /// @dev Unauthorized reentrant call
    error InitializableReentrancyGuardReentrantCall();

    /// @dev Contract was not yet initialized
    error InitializableReentrancyGuardUninitialized();

    /// @dev Contract was already initialized
    error InitializableReentrancyGuardInvalidInitialization();

    /// @notice Initializes the contract in the uninitialized state
    function __InitializeReentrancyGuard_init() internal {
        StorageStatus storage s = _getStorageStatus();

        s._status = UNINITIALIZED;
    }

    /**
     * @notice Reverts if the contract is not initialized or in case of a reentrancy
     * @dev Prevents a contract from calling itself, directly or indirectly, or using it in an uninitialized state
     * Calling an `initializedAndNonReentrant` function before the `initialize` function was called will revert
     * Calling an `initializedAndNonReentrant` function from another `initializedAndNonReentrant`
     * function is not supported
     */
    modifier initializedAndNonReentrant() {
        _checkInitialized();
        _;
    }

    /// @notice Reverts if the contract is initialized, or set it as initialized
    modifier protocolInitializer() {
        _checkUninitialized();
        _;

        StorageStatus storage s = _getStorageStatus();

        s._status = INITIALIZED;
    }

    /// @notice Reverts if the contract is not initialized
    function _checkInitialized() private view {
        StorageStatus storage s = _getStorageStatus();

        if (s._status == UNINITIALIZED) {
            revert InitializableReentrancyGuardUninitialized();
        }
    }

    /// @notice Reverts if the contract is initialized
    function _checkUninitialized() internal view {
        StorageStatus storage s = _getStorageStatus();

        if (s._status != UNINITIALIZED) {
            revert InitializableReentrancyGuardInvalidInitialization();
        }
    }
}
