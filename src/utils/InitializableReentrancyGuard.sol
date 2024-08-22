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
    /// @notice The state of the contract before entering a function
    uint256 private constant NOT_ENTERED = 1;
    /// @notice The state of the contract after entering a function
    uint256 private constant ENTERED = 2;
    /// @notice The state of the contract
    uint256 private _status;

    /// @dev Unauthorized reentrant call
    error InitializableReentrancyGuardReentrantCall();

    /// @dev Contract was not yet initialized
    error InitializableReentrancyGuardUninitialized();

    /// @dev Contract was already initialized
    error InitializableReentrancyGuardInvalidInitialization();

    /// @notice Initializes the contract in the uninitialized state
    function __initializeReentrancyGuard_init() internal {
        _status = UNINITIALIZED;
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
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    /// @notice Reverts if the contract is initialized, or set it as initialized
    modifier protocolInitializer() {
        _checkUninitialized();
        _;
        _status = NOT_ENTERED; // mark initialized
    }

    /// @notice Reverts if the contract is not initialized
    function _checkInitialized() private view {
        if (_status == UNINITIALIZED) {
            revert InitializableReentrancyGuardUninitialized();
        }
    }

    /// @notice Reverts if the contract is initialized
    function _checkUninitialized() internal view {
        if (_status != UNINITIALIZED) {
            revert InitializableReentrancyGuardInvalidInitialization();
        }
    }

    /// @notice Reverts if `_status` is ENTERED``, or set `_status` to `ENTERED`
    function _nonReentrantBefore() private {
        // on the first call to `nonReentrant`, `_status` will be `NOT_ENTERED`
        if (_status == ENTERED) {
            revert InitializableReentrancyGuardReentrantCall();
        }

        // any calls to `nonReentrant` after this point will fail
        _status = ENTERED;
    }

    /// @notice Set `_status` to `NOT_ENTERED`
    function _nonReentrantAfter() private {
        // by storing the original value once again, a refund is triggered (see https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }
}
