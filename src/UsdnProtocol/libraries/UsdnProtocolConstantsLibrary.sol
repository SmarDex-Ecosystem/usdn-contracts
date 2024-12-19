// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

library UsdnProtocolConstantsLibrary {
    /// @notice Number of decimals used for a position's leverage.
    uint8 internal constant LEVERAGE_DECIMALS = 21;

    /// @notice Number of decimals used for the funding rate.
    uint8 internal constant FUNDING_RATE_DECIMALS = 18;

    /// @notice Number of decimals used for tokens within the protocol (excluding the asset).
    uint8 internal constant TOKENS_DECIMALS = 18;

    /// @notice Number of decimals used for the fixed representation of the liquidation multiplier.
    uint8 internal constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;

    /// @notice Number of decimals in the scaling factor of the funding rate.
    uint8 internal constant FUNDING_SF_DECIMALS = 3;

    /**
     * @notice Minimum leverage allowed for the rebalancer to open a position.
     * @dev In edge cases where the rebalancer holds significantly more assets than the protocol,
     * opening a position with the protocol's minimum leverage could cause a large overshoot of the target,
     * potentially creating an even greater imbalance. To prevent this, the rebalancer can use leverage
     * as low as the technical minimum (10 ** LEVERAGE_DECIMALS + 1).
     */
    uint256 internal constant REBALANCER_MIN_LEVERAGE = 10 ** LEVERAGE_DECIMALS + 1; // x1.000000000000000000001

    /// @notice Divisor for the ratio of USDN to SDEX burned on deposit.
    uint256 internal constant SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;

    /// @notice Divisor for basis point (BPS) values.
    uint256 internal constant BPS_DIVISOR = 10_000;

    /// @notice Maximum number of tick liquidations that can be processed per call.
    uint16 internal constant MAX_LIQUIDATION_ITERATION = 10;

    /// @notice Sentinel value indicating a `PositionId` that represents no position.
    int24 internal constant NO_POSITION_TICK = type(int24).min;

    /// @notice Address holding the minimum supply of USDN and the first minimum long position.
    address internal constant DEAD_ADDRESS = address(0xdead);

    /**
     * @notice Delay after which a blocked pending action can be removed after `_lowLatencyValidatorDeadline` +
     * `_onChainValidatorDeadline`.
     */
    uint16 internal constant REMOVE_BLOCKED_PENDING_ACTIONS_DELAY = 5 minutes;

    /**
     * @notice Minimum total supply of USDN allowed.
     * @dev Upon the first deposit, this amount is sent to the dead address and becomes unrecoverable.
     */
    uint256 internal constant MIN_USDN_SUPPLY = 1000;

    /**
     * @notice Minimum margin between total exposure and long balance.
     * @dev Ensures the balance long does not increase in a way that causes the trading exposure to
     * fall below this margin. If this occurs, the balance long is clamped to the total exposure minus the margin.
     */
    uint256 internal constant MIN_LONG_TRADING_EXPO_BPS = 100;

    /* -------------------------------------------------------------------------- */
    /*                                   Setters                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Minimum iterations when searching for actionable pending actions in {getActionablePendingActions}.
    uint256 internal constant MIN_ACTIONABLE_PENDING_ACTIONS_ITER = 20;

    /// @notice Minimum validation deadline for validators.
    uint256 internal constant MIN_VALIDATION_DEADLINE = 60;

    /// @notice Maximum validation deadline for validators.
    uint256 internal constant MAX_VALIDATION_DEADLINE = 1 days;

    /// @notice Maximum liquidation penalty allowed.
    uint256 internal constant MAX_LIQUIDATION_PENALTY = 1500;

    /// @notice Maximum safety margin allowed in basis points.
    uint256 internal constant MAX_SAFETY_MARGIN_BPS = 2000;

    /// @notice Maximum EMA (Exponential Moving Average) period allowed.
    uint256 internal constant MAX_EMA_PERIOD = 90 days;

    /// @notice Maximum position fee allowed in basis points.
    uint256 internal constant MAX_POSITION_FEE_BPS = 2000;

    /// @notice Maximum vault fee allowed in basis points.
    uint256 internal constant MAX_VAULT_FEE_BPS = 2000;

    /// @notice Maximum ratio of SDEX rewards allowed in basis points.
    uint256 internal constant MAX_SDEX_REWARDS_RATIO_BPS = 1000;

    /// @notice Maximum ratio of SDEX to burn per minted USDN on deposit (10%).
    uint256 internal constant MAX_SDEX_BURN_RATIO = SDEX_BURN_ON_DEPOSIT_DIVISOR / 10;

    /// @notice Maximum leverage allowed.
    uint256 internal constant MAX_LEVERAGE = 100 * 10 ** LEVERAGE_DECIMALS;

    /// @notice Maximum security deposit allowed.
    uint256 internal constant MAX_SECURITY_DEPOSIT = 5 ether;

    /// @notice The highest value allowed for the minimum long position setting.
    uint256 internal constant MAX_MIN_LONG_POSITION = 10 ether;

    /// @notice Maximum protocol fee allowed in basis points.
    uint16 internal constant MAX_PROTOCOL_FEE_BPS = 3000;

    /* -------------------------------------------------------------------------- */
    /*                                   EIP712                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice EIP712 typehash for {initiateClosePosition}.
     * @dev Used within EIP712 messages for domain-specific signing, enabling recovery of the signer
     * via [ECDSA-recover](https://docs.openzeppelin.com/contracts/5.x/api/utils#ECDSA).
     */
    bytes32 internal constant INITIATE_CLOSE_TYPEHASH = keccak256(
        "InitiateClosePositionDelegation(bytes32 posIdHash,uint128 amountToClose,uint256 userMinPrice,address to,uint256 deadline,address positionOwner,address positionCloser,uint256 nonce)"
    );

    /**
     * @notice EIP712 typehash for {transferPositionOwnership}.
     * @dev Used within EIP712 messages for domain-specific signing, enabling recovery of the signer
     * via [ECDSA-recover](https://docs.openzeppelin.com/contracts/5.x/api/utils#ECDSA).
     */
    bytes32 internal constant TRANSFER_POSITION_OWNERSHIP_TYPEHASH = keccak256(
        "TransferPositionOwnershipDelegation(bytes32 posIdHash,address positionOwner,address newPositionOwner,address delegatedAddress,uint256 nonce)"
    );

    /* -------------------------------------------------------------------------- */
    /*                                Roles hashes                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Role signature for setting external contracts.
    bytes32 public constant SET_EXTERNAL_ROLE = keccak256("SET_EXTERNAL_ROLE");

    /// @notice Role signature for performing critical protocol actions.
    bytes32 public constant CRITICAL_FUNCTIONS_ROLE = keccak256("CRITICAL_FUNCTIONS_ROLE");

    /// @notice Role signature for setting protocol parameters.
    bytes32 public constant SET_PROTOCOL_PARAMS_ROLE = keccak256("SET_PROTOCOL_PARAMS_ROLE");

    /// @notice Role signature for setting USDN parameters.
    bytes32 public constant SET_USDN_PARAMS_ROLE = keccak256("SET_USDN_PARAMS_ROLE");

    /// @notice Role signature for configuring protocol options with minimal impact.
    bytes32 public constant SET_OPTIONS_ROLE = keccak256("SET_OPTIONS_ROLE");

    /// @notice Role signature for upgrading the protocol implementation.
    bytes32 public constant PROXY_UPGRADE_ROLE = keccak256("PROXY_UPGRADE_ROLE");

    /// @notice Role signature for pausing the protocol.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role signature for unpausing the protocol.
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    /// @notice Admin role for managing the `SET_EXTERNAL_ROLE`.
    bytes32 public constant ADMIN_SET_EXTERNAL_ROLE = keccak256("ADMIN_SET_EXTERNAL_ROLE");

    /// @notice Admin role for managing the `CRITICAL_FUNCTIONS_ROLE`.
    bytes32 public constant ADMIN_CRITICAL_FUNCTIONS_ROLE = keccak256("ADMIN_CRITICAL_FUNCTIONS_ROLE");

    /// @notice Admin role for managing the `SET_PROTOCOL_PARAMS_ROLE`.
    bytes32 public constant ADMIN_SET_PROTOCOL_PARAMS_ROLE = keccak256("ADMIN_SET_PROTOCOL_PARAMS_ROLE");

    /// @notice Admin role for managing the `SET_USDN_PARAMS_ROLE`.
    bytes32 public constant ADMIN_SET_USDN_PARAMS_ROLE = keccak256("ADMIN_SET_USDN_PARAMS_ROLE");

    /// @notice Admin role for managing the `SET_OPTIONS_ROLE`.
    bytes32 public constant ADMIN_SET_OPTIONS_ROLE = keccak256("ADMIN_SET_OPTIONS_ROLE");

    /// @notice Admin role for managing the `PROXY_UPGRADE_ROLE`.
    bytes32 public constant ADMIN_PROXY_UPGRADE_ROLE = keccak256("ADMIN_PROXY_UPGRADE_ROLE");

    /// @notice Admin role for managing the `PAUSER_ROLE`.
    bytes32 public constant ADMIN_PAUSER_ROLE = keccak256("ADMIN_PAUSER_ROLE");

    /// @notice Admin role for managing the `UNPAUSER_ROLE`.
    bytes32 public constant ADMIN_UNPAUSER_ROLE = keccak256("ADMIN_UNPAUSER_ROLE");
}
