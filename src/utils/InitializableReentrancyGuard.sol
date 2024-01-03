// SPDX-License-Identifier: MIT
// Based on the OpenZeppelin implementation

pragma solidity ^0.8.20;

/**
 * @title InitializableReentrancyGuard
 * @dev Contract module that helps prevent reentrant calls to a function and ensures the initializer has been called.
 */
abstract contract InitializableReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.
    uint256 private constant UNINITIALIZED = 0;
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /// @dev Unauthorized reentrant call.
    error InitializableReentrancyGuardReentrantCall();

    /// @dev Contract was not yet initialized.
    error InitializableReentrancyGuardUninitialized();

    /// @dev Contract was already initialized.
    error InitializableReentrancyGuardInvalidInitialization();

    constructor() {
        _status = UNINITIALIZED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly, or using it in an uninitialized state.
     * Calling a `initializedAndNonReentrant` function before the `initialize` function was called will revert.
     * Calling a `initializedAndNonReentrant` function from another `initializedAndNonReentrant`
     * function is not supported.
     */
    modifier initializedAndNonReentrant() {
        _checkInitialized();
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    modifier initializer() {
        _checkUninitialized();
        _;
        _status = NOT_ENTERED; // mark initialized
    }

    function _checkInitialized() private view {
        if (_status == UNINITIALIZED) {
            revert InitializableReentrancyGuardUninitialized();
        }
    }

    function _checkUninitialized() private view {
        if (_status != UNINITIALIZED) {
            revert InitializableReentrancyGuardInvalidInitialization();
        }
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert InitializableReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }
}
