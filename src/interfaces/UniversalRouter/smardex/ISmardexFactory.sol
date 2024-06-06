// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.17;

interface ISmardexFactory {
    /**
     * @notice emitted at each SmardexPair created
     * @param token0 address of the token0
     * @param token1 address of the token1
     * @param pair address of the SmardexPair created
     * @param totalPair number of SmardexPair created so far
     */
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 totalPair);

    /**
     * @notice emitted at each SmardexPair manually added
     * @param token0 address of the token0
     * @param token1 address of the token1
     * @param pair address of the SmardexPair created
     * @param totalPair number of SmardexPair created so far
     */
    event PairAdded(address indexed token0, address indexed token1, address pair, uint256 totalPair);

    /**
     * @notice emitted each time feesLP and feesPool are changed
     * @param feesLP new feesLP
     * @param feesPool new feesPool
     */
    event FeesChanged(uint256 indexed feesLP, uint256 indexed feesPool);

    /**
     * @notice emitted when the feeTo is updated
     * @param previousFeeTo the previous feeTo address
     * @param newFeeTo the new feeTo address
     */
    event FeeToUpdated(address indexed previousFeeTo, address indexed newFeeTo);

    /// @return Which the address fees will be transferred
    function feeTo() external view returns (address);

    /**
     * @param tokenA The token A of the pair
     * @param tokenB The token B of the pair
     * @return pair_ The address of the pair of 2 tokens
     */
    function getPair(address tokenA, address tokenB) external view returns (address pair_);

    /**
     * @notice return the address of the pair at index
     * @param index index of the pair
     * @return pair_ address of the pair
     */
    function allPairs(uint256 index) external view returns (address pair_);

    /// @return The quantity of pairs
    function allPairsLength() external view returns (uint256);

    /**
     * @notice return numerators of pair fees, denominator is 1_000_000
     * @return feesLP_ numerator of fees sent to LP at pair creation
     * @return feesPool_ numerator of fees sent to Pool at pair creation
     */
    function getDefaultFees() external view returns (uint128 feesLP_, uint128 feesPool_);

    /**
     * @notice whether whitelist is open
     * @return open_ true if the whitelist is open, false otherwise
     */
    function whitelistOpen() external view returns (bool open_);

    /**
     * @notice create pair with 2 address
     * @param tokenA address of tokenA
     * @param tokenB address of tokenB
     * @return pair_ address of the pair created
     */
    function createPair(address tokenA, address tokenB) external returns (address pair_);

    /**
     * @notice set the address who will receive fees, can only be call by the owner
     * @param feeTo address to replace
     */
    function setFeeTo(address feeTo) external;

    /**
     * @notice set feesLP and feesPool for each new pair (onlyOwner)
     * @notice sum of new feesLp and feesPool must be <= FEES_MAX = 10% FEES_BASE
     * @param feesLP new numerator of fees sent to LP, must be >= 1
     * @param feesPool new numerator of fees sent to Pool, could be = 0
     */
    function setFees(uint128 feesLP, uint128 feesPool) external;

    /**
     * @notice disable whitelist (onlyOwner)
     * whitelist cannot be re-opened after that.
     */
    function closeWhitelist() external;

    /**
     * @notice add a pair manually
     * @param pair pair address to add (must be an ISmardexPair)
     */
    function addPair(address pair) external;
}
