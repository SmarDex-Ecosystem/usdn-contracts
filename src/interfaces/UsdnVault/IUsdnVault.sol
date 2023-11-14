// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                                   Structs                                  */
/* -------------------------------------------------------------------------- */

/// @dev 32 bytes packed struct representing a position waiting for a commitment.
///      It can be a short entry, a short exit, a long entry or a long exit.
/// NOTE: The leverage is 0 if the position is a short.
struct Position {
    uint40 leverage; // Max 1_099_511_627_775 (1_099 with 9 decimals)
    uint40 timestamp; // Max 1_099_511_627_775 (20/02/36812 01:36:15)
    bool isExit;
    bool validated;
    address user;
    uint128 amount;
    uint128 startPrice;
}

/// @dev 32 bytes packed struct representing the metadata of a position waiting
///      for a commitment.
struct PendingPositionMetadata {
    int24 tick;
    uint64 gasPrice;
    uint168 index;
}

/// @title USDN Vault
/// @notice This contract is the USDN Vault.
/// @dev This contract is used to manage the long and short positions.
/// @author @yahiru
/// @author @beeb
interface IUsdnVault {
    /* -------------------------------------------------------------------------- */
    /*                            Only owner functions                            */
    /* -------------------------------------------------------------------------- */

    /// @notice Initialize the vault.
    /// @dev To be called once the vault is authorized to transfer the asset.
    function initialize(uint256 _depositShort, uint96 _depositLong, uint128 _currentPrice) external;

    /// @notice Manually set the funding rate.
    /// @param _fundingRatePerSecond The new funding rate.
    function setFundingRate(int256 _fundingRatePerSecond) external;

    /// @notice Set the min and max leverage.
    /// @param _minLeverage The new min leverage.
    /// @param _maxLeverage The new max leverage.
    function setMinMaxLeverage(uint256 _minLeverage, uint256 _maxLeverage) external;

    /// @notice Set the oracle middleware address.
    /// @param _oracleMiddleware The new oracle middleware address.
    function setOracleMiddleware(address _oracleMiddleware) external;
}
