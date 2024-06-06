// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.17;

interface ISmardexSwapRouter {
    /**
     * @notice callback data for smardex swap
     * @param amount0Delta amount of token0 for the swap (negative is incoming, positive is required to pay to pair)
     * @param amount1Delta amount of token1 for the swap (negative is incoming, positive is required to pay to pair)
     * @param data for Router path and payer for the swap
     */
    function smardexSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}
