// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

library UsdnProtocolConstantsLibrary {
    uint8 internal constant LEVERAGE_DECIMALS = 21;
    uint256 internal constant REBALANCER_MIN_LEVERAGE = 10 ** LEVERAGE_DECIMALS + 1; // x1.000000000000000000001
    uint8 internal constant FUNDING_RATE_DECIMALS = 18;
    uint8 internal constant TOKENS_DECIMALS = 18;
    uint8 internal constant LIQUIDATION_MULTIPLIER_DECIMALS = 38;
    uint8 internal constant FUNDING_SF_DECIMALS = 3;
    uint256 internal constant SDEX_BURN_ON_DEPOSIT_DIVISOR = 1e8;
    uint256 internal constant BPS_DIVISOR = 10_000;
    uint16 internal constant MAX_LIQUIDATION_ITERATION = 10;
    int24 internal constant NO_POSITION_TICK = type(int24).min;
    address internal constant DEAD_ADDRESS = address(0xdead);
    uint256 internal constant MIN_USDN_SUPPLY = 1000;
    uint256 internal constant MIN_ACTIONABLE_PENDING_ACTIONS_ITER = 20;
    uint256 internal constant MIN_VALIDATION_DEADLINE = 60;
    uint256 internal constant MAX_VALIDATION_DEADLINE = 1 days;
    uint256 internal constant MAX_LIQUIDATION_PENALTY = 1500;
    uint256 internal constant MAX_SAFETY_MARGIN_BPS = 2000;
    uint256 internal constant MAX_EMA_PERIOD = 90 days;
    uint256 internal constant MAX_POSITION_FEE_BPS = 2000;
    uint256 internal constant MAX_VAULT_FEE_BPS = 2000;
    uint256 internal constant MAX_LEVERAGE = 100 * 10 ** LEVERAGE_DECIMALS;
    uint256 internal constant MAX_SECURITY_DEPOSIT = 5 ether;
    uint256 internal constant MAX_MIN_LONG_POSITION = 10 ether;
    uint16 internal constant MAX_PROTOCOL_FEE_BPS = 3000;
    uint16 internal constant REMOVE_BLOCKED_PENDING_ACTIONS_DELAY = 5 minutes;

    // After some checks, 1% would mean a user with a position with 10x leverage needs the price to 900x before it
    // limits the position's PnL. We think it's unlikely enough so we don't consider it a problem
    uint256 internal constant MIN_LONG_TRADING_EXPO_BPS = 100;

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

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_EXTERNAL_ROLE = keccak256("SET_EXTERNAL_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant CRITICAL_FUNCTIONS_ROLE = keccak256("CRITICAL_FUNCTIONS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_PROTOCOL_PARAMS_ROLE = keccak256("SET_PROTOCOL_PARAMS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_USDN_PARAMS_ROLE = keccak256("SET_USDN_PARAMS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant SET_OPTIONS_ROLE = keccak256("SET_OPTIONS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant PROXY_UPGRADE_ROLE = keccak256("PROXY_UPGRADE_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_EXTERNAL_ROLE = keccak256("ADMIN_SET_EXTERNAL_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_CRITICAL_FUNCTIONS_ROLE = keccak256("ADMIN_CRITICAL_FUNCTIONS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_PROTOCOL_PARAMS_ROLE = keccak256("ADMIN_SET_PROTOCOL_PARAMS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_USDN_PARAMS_ROLE = keccak256("ADMIN_SET_USDN_PARAMS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_SET_OPTIONS_ROLE = keccak256("ADMIN_SET_OPTIONS_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_PROXY_UPGRADE_ROLE = keccak256("ADMIN_PROXY_UPGRADE_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_PAUSER_ROLE = keccak256("ADMIN_PAUSER_ROLE");

    // / @inheritdoc IUsdnProtocolStorage
    bytes32 public constant ADMIN_UNPAUSER_ROLE = keccak256("ADMIN_UNPAUSER_ROLE");
}
