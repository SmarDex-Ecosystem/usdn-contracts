// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

library UsdnProtocolConstantsLibrary {
    /**
     * @notice The minimum leverage allowed for the rebalancer to open a position
     * @dev In edge cases where the rebalancer holds significantly more assets than the protocol, opening a position
     * with the protocol's minimum leverage could cause a large overshoot of the target, potentially creating even
     * greater imbalance than before the trigger. To prevent this, the rebalancer can use leverage as low as the
     * technical minimum (10**LEVERAGE_DECIMALS + 1)
     */
    uint256 internal constant REBALANCER_MIN_LEVERAGE = 10 ** LEVERAGE_DECIMALS + 1; // x1.000000000000000000001

    /// @notice The number of decimals of a position's leverage
    uint8 internal constant LEVERAGE_DECIMALS = 21;

    /// @notice The number of decimals of the funding rate
    uint8 internal constant FUNDING_RATE_DECIMALS = 18;

    /// @notice The number of decimals of tokens used in the protocol (except the asset)
    uint8 internal constant TOKENS_DECIMALS = 18;

    /// @notice The number of decimals used for the fixed representation of the liquidation multiplier
    uint8 internal constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;

    /// @notice The number of decimals in the scaling factor of the funding rate
    uint8 internal constant FUNDING_SF_DECIMALS = 3;

    /// @notice The divisor for the ratio of USDN to SDEX to burn on deposit
    uint256 internal constant SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;

    /// @notice The divisor for basis point values
    uint256 internal constant BPS_DIVISOR = 10_000;

    /// @notice The maximum number of tick liquidations that can be done per call
    uint16 internal constant MAX_LIQUIDATION_ITERATION = 10;

    /// @notice The sentinel value indicating that a `PositionId` represents no position
    int24 internal constant NO_POSITION_TICK = type(int24).min;

    /// @notice The address that holds the minimum supply of USDN and the first minimum long position
    address internal constant DEAD_ADDRESS = address(0xdead);

    /**
     * @notice The delay after which a blocked pending action can be removed
     * @dev After `_lowLatencyValidatorDeadline` + `_onChainValidatorDeadline`
     */
    uint16 internal constant REMOVE_BLOCKED_PENDING_ACTIONS_DELAY = 5 minutes;

    /**
     * @notice The minimum total supply of USDN that we allow
     * @dev Upon the first deposit, this amount is sent to the dead address and cannot be later recovered
     */
    uint256 internal constant MIN_USDN_SUPPLY = 1000;

    /**
     * @notice The lowest margin between the total expo and the balance long
     * @dev The balance long cannot increase in a way that makes the trading expo worth less than the margin
     * If that happens, the balance long will be clamped down to the total expo minus the margin
     * After some checks, 1% would mean a user with a position with 10x leverage needs the price to 900x before it
     * limits the position's PnL. We think it's unlikely enough so we don't consider it a problem
     */
    uint256 internal constant MIN_LONG_TRADING_EXPO_BPS = 100;

    /* -------------------------------------------------------------------------- */
    /*                                   Setters                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice The minimum number of iterations when searching for actionable pending actions in
    /// {getActionablePendingActions} that can be set
    uint256 internal constant MIN_ACTIONABLE_PENDING_ACTIONS_ITER = 20;

    /// @notice The minimum validation deadline for validators that can be set
    uint256 internal constant MIN_VALIDATION_DEADLINE = 60;

    /// @notice The maximum validation deadline for validators that can be set
    uint256 internal constant MAX_VALIDATION_DEADLINE = 1 days;

    /// @notice The maximum liquidation penalty that can be set
    uint256 internal constant MAX_LIQUIDATION_PENALTY = 1500;

    /// @notice The maximum safety margin that can be set
    uint256 internal constant MAX_SAFETY_MARGIN_BPS = 2000;

    /// @notice The maximum EMA period that can be set
    uint256 internal constant MAX_EMA_PERIOD = 90 days;

    /// @notice The maximum position fee that can be set
    uint256 internal constant MAX_POSITION_FEE_BPS = 2000;

    /// @notice The maximum vault fee that can be set
    uint256 internal constant MAX_VAULT_FEE_BPS = 2000;

    /// @notice The maximum leverage that can be set
    uint256 internal constant MAX_LEVERAGE = 100 * 10 ** LEVERAGE_DECIMALS;

    /// @notice The maximum security deposit that can be set
    uint256 internal constant MAX_SECURITY_DEPOSIT = 5 ether;

    /// @notice The maximum minimum long position that can be set
    uint256 internal constant MAX_MIN_LONG_POSITION = 10 ether;

    /// @notice The maximum protocol fee that can be set
    uint16 internal constant MAX_PROTOCOL_FEE_BPS = 3000;

    /* -------------------------------------------------------------------------- */
    /*                                   EIP712                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The EIP712 {initiateClosePosition} typehash
     * @dev By including this hash into the EIP712 message for this domain, this can be used together with
     * {ECDSA-recover} to obtain the signer of a message
     */
    bytes32 internal constant INITIATE_CLOSE_TYPEHASH = keccak256(
        "InitiateClosePositionDelegation(bytes32 posIdHash,uint128 amountToClose,uint256 userMinPrice,address to,uint256 deadline,address positionOwner,address positionCloser,uint256 nonce)"
    );

    /**
     * @notice The EIP712 {transferPositionOwnership} typehash
     * @dev By including this hash into the EIP712 message for this domain, this can be used together with
     * {ECDSA-recover} to obtain the signer of a message
     */
    bytes32 internal constant TRANSFER_POSITION_OWNERSHIP_TYPEHASH = keccak256(
        "TransferPositionOwnershipDelegation(bytes32 posIdHash,address positionOwner,address newPositionOwner,address delegatedAddress,uint256 nonce)"
    );

    /* -------------------------------------------------------------------------- */
    /*                                Roles hashes                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice The SET_EXTERNAL_ROLE role's signature
     * @dev This role is used to set the external contracts
     */
    bytes32 public constant SET_EXTERNAL_ROLE = keccak256("SET_EXTERNAL_ROLE");

    /**
     * @notice The CRITICAL_FUNCTIONS_ROLE role's signature
     * @dev This role is used to perform critical actions
     */
    bytes32 public constant CRITICAL_FUNCTIONS_ROLE = keccak256("CRITICAL_FUNCTIONS_ROLE");

    /**
     * @notice The SET_PROTOCOL_PARAMS_ROLE role's signature
     * @dev This role is used to set the protocol parameters
     */
    bytes32 public constant SET_PROTOCOL_PARAMS_ROLE = keccak256("SET_PROTOCOL_PARAMS_ROLE");

    /**
     * @notice The SET_USDN_PARAMS_ROLE role's signature
     * @dev This role is used to set the protocol parameters
     */
    bytes32 public constant SET_USDN_PARAMS_ROLE = keccak256("SET_USDN_PARAMS_ROLE");

    /**
     * @notice The SET_OPTIONS_ROLE role's signature
     * @dev This role is used to set the protocol options that do not impact the usage of the protocol
     */
    bytes32 public constant SET_OPTIONS_ROLE = keccak256("SET_OPTIONS_ROLE");

    /**
     * @notice The PROXY_UPGRADE_ROLE role's signature
     * @dev This role is used to upgrade the protocol implementation
     */
    bytes32 public constant PROXY_UPGRADE_ROLE = keccak256("PROXY_UPGRADE_ROLE");

    /**
     * @notice The PAUSER_ROLE role's signature
     * @dev This role is used to pause the protocol
     */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @notice The UNPAUSER_ROLE role's signature
     * @dev This role is used to unpause the protocol
     */
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /**
     * @notice The ADMIN_SET_EXTERNAL_ROLE role's signature
     * @dev This role is used to revoke and grant the {SET_EXTERNAL_ROLE} role
     */
    bytes32 public constant ADMIN_SET_EXTERNAL_ROLE = keccak256("ADMIN_SET_EXTERNAL_ROLE");

    /**
     * @notice The ADMIN_CRITICAL_FUNCTIONS_ROLE role's signature
     * @dev This role is used to revoke and grant the {CRITICAL_FUNCTIONS_ROLE} role
     */
    bytes32 public constant ADMIN_CRITICAL_FUNCTIONS_ROLE = keccak256("ADMIN_CRITICAL_FUNCTIONS_ROLE");

    /**
     * @notice The ADMIN_SET_PROTOCOL_PARAMS_ROLE role's signature
     * @dev This role is used to revoke and grant the {SET_PROTOCOL_PARAMS_ROLE} role
     */
    bytes32 public constant ADMIN_SET_PROTOCOL_PARAMS_ROLE = keccak256("ADMIN_SET_PROTOCOL_PARAMS_ROLE");

    /**
     * @notice The ADMIN_SET_USDN_PARAMS_ROLE role's signature
     * @dev This role is used to revoke and grant the {SET_USDN_PARAMS_ROLE} role
     */
    bytes32 public constant ADMIN_SET_USDN_PARAMS_ROLE = keccak256("ADMIN_SET_USDN_PARAMS_ROLE");

    /**
     * @notice The ADMIN_SET_OPTIONS_ROLE role's signature
     * @dev This role is used to revoke and grant the {SET_OPTIONS_ROLE} role
     */
    bytes32 public constant ADMIN_SET_OPTIONS_ROLE = keccak256("ADMIN_SET_OPTIONS_ROLE");

    /**
     * @notice The ADMIN_PROXY_UPGRADE_ROLE role's signature
     * @dev This role is used to revoke and grant the {PROXY_UPGRADE_ROLE} role
     */
    bytes32 public constant ADMIN_PROXY_UPGRADE_ROLE = keccak256("ADMIN_PROXY_UPGRADE_ROLE");

    /**
     * @notice The ADMIN_PAUSER_ROLE role's signature
     * @dev This role is used to revoke and grant the {PAUSER_ROLE} role
     */
    bytes32 public constant ADMIN_PAUSER_ROLE = keccak256("ADMIN_PAUSER_ROLE");

    /**
     * @notice The ADMIN_UNPAUSER_ROLE role's signature
     * @dev This role is used to revoke and grant the {UNPAUSER_ROLE} role
     */
    bytes32 public constant ADMIN_UNPAUSER_ROLE = keccak256("ADMIN_UNPAUSER_ROLE");
}
