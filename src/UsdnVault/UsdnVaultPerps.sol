// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                             External libraries                             */
/* -------------------------------------------------------------------------- */

/* ------------------------------ Open Zeppelin ----------------------------- */

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/* -------------------------------------------------------------------------- */
/*                              Internal imports                              */
/* -------------------------------------------------------------------------- */

import { TickBitmap } from "src/libraries/TickBitmap.sol";
import { UsdnVaultCore } from "./UsdnVaultCore.sol";
import { IOracleMiddleware, PriceInfo, ProtocolAction } from "src/interfaces/IOracleMiddleware.sol";
import { IUsdnVaultPerps } from "../interfaces/UsdnVault/IUsdnVaultPerps.sol";
import { Position } from "../interfaces/UsdnVault/IUsdnVault.sol";
import { TickMath } from "src/libraries/TickMath128.sol";

import {
    AccessDenied,
    IncompleteTransfer,
    InvalidPendingPosition,
    LeverageTooLow,
    LeverageTooHigh,
    NoPendingPosition,
    MinTotalSupply,
    ZeroAmount
} from "../utils/Errors.sol";

contract UsdnVaultPerps is IUsdnVaultPerps, UsdnVaultCore {
    // Safe ERC20 and Tick bitmap
    using SafeERC20 for IERC20Metadata;
    using TickBitmap for mapping(int16 => uint256);

    /* -------------------------------------------------------------------------- */
    /*                                 Constructor                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Constructor.
    /// @param _asset The asset ERC20 contract.
    /// @param _oracleMiddleware The oracle middleware contract.
    /// @param _tickSpacing The positions tick spacing.
    constructor(IERC20Metadata _asset, IOracleMiddleware _oracleMiddleware, int24 _tickSpacing)
        UsdnVaultCore(_asset, _oracleMiddleware, _tickSpacing)
    { }

    /* -------------------------------------------------------------------------- */
    /*                             External functions                             */
    /* -------------------------------------------------------------------------- */

    /* ----------------------------- Bot validation ----------------------------- */

    /// @inheritdoc IUsdnVaultPerps
    function liquidate(uint256 maxIter, bytes calldata priceData) external payable returns (uint256 liquidated) {
        // FIXME: which price and timestamp do we provide to the oracle middleware?
        PriceInfo memory currentPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint128(block.timestamp), ProtocolAction.LiquidatePosition, priceData
        );
        // we will iterate at least once because of the do-while loop
        _applyPnlAndFunding(currentPrice.price, currentPrice.timestamp);
        liquidated = _liquidate(currentPrice.price, maxIter);
    }

    /* ------------------------------ Long features ----------------------------- */

    /// @inheritdoc IUsdnVaultPerps
    function openLong(uint96 _amount, uint128 _liquidationPrice) external payable returns (int24, uint256) {
        return _openLong(_amount, _liquidationPrice);
    }

    /// @inheritdoc IUsdnVaultPerps
    function openLong(uint96 _amount, uint128 _liquidationPrice, bytes calldata _previousActionPriceData)
        external
        payable
        returns (int24, uint256)
    {
        _validatePreviousActionPrice(_previousActionPriceData);

        return _openLong(_amount, _liquidationPrice);
    }

    /// @inheritdoc IUsdnVaultPerps
    function closeLong(int24 _tick, uint256 _index, bytes calldata _currentOraclePriceData)
        external
        payable
        returns (int24, uint256)
    {
        return _closeLong(_tick, _index, _currentOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function closeLong(
        int24 _tick,
        uint256 _index,
        bytes calldata _currentOraclePriceData,
        bytes calldata _previousActionPriceData
    ) external payable returns (int24, uint256) {
        _validatePreviousActionPrice(_previousActionPriceData);

        return _closeLong(_tick, _index, _currentOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function validateLong(int24 _tick, uint256 _index, bytes calldata _finalOraclePriceData) external payable {
        _validateLong(_tick, _index, _finalOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function validateLong(
        int24 _tick,
        uint256 _index,
        bytes calldata _finalOraclePriceData,
        bytes calldata _previousActionPriceData
    ) external payable {
        _validatePreviousActionPrice(_previousActionPriceData);

        _validateLong(_tick, _index, _finalOraclePriceData);
    }

    /* ----------------------------- Short features ----------------------------- */

    /// @inheritdoc IUsdnVaultPerps
    function deposit(uint128 amount, bytes calldata _currentOraclePriceData) external payable {
        _deposit(amount, _currentOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function deposit(uint128 amount, bytes calldata _currentOraclePriceData, bytes calldata _previousActionPriceData)
        external
        payable
    {
        _validatePreviousActionPrice(_previousActionPriceData);

        _deposit(amount, _currentOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function withdraw(uint128 amount, bytes calldata _currentOraclePriceData) external payable {
        _withdraw(amount, _currentOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function withdraw(uint128 amount, bytes calldata _currentOraclePriceData, bytes calldata _previousActionPriceData)
        external
        payable
    {
        _validatePreviousActionPrice(_previousActionPriceData);

        _withdraw(amount, _currentOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function validateShort(bytes calldata _finalOraclePriceData) external payable {
        _validateShort(_finalOraclePriceData);
    }

    /// @inheritdoc IUsdnVaultPerps
    function validateShort(bytes calldata _finalOraclePriceData, bytes calldata _previousActionPriceData)
        external
        payable
    {
        _validatePreviousActionPrice(_previousActionPriceData);

        _validateShort(_finalOraclePriceData);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Public functions                              */
    /* -------------------------------------------------------------------------- */

    /* ----------------------------- View functions ----------------------------- */

    /// @inheritdoc IUsdnVaultPerps
    function getLongPosition(int24 tick, uint256 index) public view returns (Position memory pos) {
        pos = longPositions[_tickHash(tick)][index];
    }

    /// @inheritdoc IUsdnVaultPerps
    function getLongPositionsLength(int24 tick) external view returns (uint256 len) {
        len = positionsInTick[_tickHash(tick)];
    }

    /// @inheritdoc IUsdnVaultPerps
    function usdnPrice(uint128 currentPrice) external view returns (uint256 usdn) {
        usdn = uint256(
            (shortAssetAvailable(currentPrice) + fundingAsset(currentPrice, uint128(block.timestamp)))
                * int256(uint256(currentPrice)) * int256(10) ** usdn.decimals()
        ) / (usdn.totalSupply() * 10 ** assetDecimals);
    }

    /* ----------------------------- Pure functions ----------------------------- */

    /// @inheritdoc IUsdnVaultPerps
    function getLiquidationPrice(uint128 startPrice, uint40 leverage) public pure returns (uint128 price) {
        price = startPrice - ((uint128(10) ** LEVERAGE_DECIMALS * startPrice) / leverage);
    }

    /// @inheritdoc IUsdnVaultPerps
    function getLeverage(uint128 startPrice, uint128 liquidationPrice) public pure returns (uint40 leverage) {
        leverage = uint40((uint128(10) ** LEVERAGE_DECIMALS * startPrice) / (startPrice - liquidationPrice));
    }

    /// @inheritdoc IUsdnVaultPerps
    function positionValue(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        public
        pure
        returns (int256 value)
    {
        value = int256(uint256(amount)) + positionPnl(currentPrice, startPrice, amount, leverage);
    }

    /// @inheritdoc IUsdnVaultPerps
    function positionPnl(uint128 currentPrice, uint128 startPrice, uint128 amount, uint40 leverage)
        public
        pure
        returns (int256 pnl)
    {
        int256 priceDiff = int256(uint256(currentPrice)) - int256(uint256(startPrice));
        pnl = (int256(uint256(amount)) * priceDiff * int256(uint256(leverage)))
            / (int256(uint256(startPrice)) * int256(10) ** LEVERAGE_DECIMALS);
    }

    /* -------------------------------------------------------------------------- */
    /*                              Internal Function                             */
    /* -------------------------------------------------------------------------- */

    /// @dev Liquidate all positions above the current price.
    ///         Note: MaxIter is used to limit the number of iterations.
    /// @param currentPrice The current price.
    /// @param maxIter The maximum number of iterations.
    /// @return liquidated The number of liquidated positions.
    function _liquidate(uint128 currentPrice, uint256 maxIter) internal returns (uint256 liquidated) {
        int24 currentTick =
            TickMath.getClosestTickAtPrice(TickMath.fromDecimal(int256(uint256(currentPrice)), priceFeedDecimals));
        int24 tick = maxInitializedTick + 1;
        uint256 i;
        do {
            unchecked {
                ++i;
            }
            (int24 next, bool initialized) = tickBitmap.nextInitializedTickWithinOneWord(tick - 1, tickSpacing, true);
            tick = next;
            if (tick < currentTick) {
                break;
            }
            if (!initialized) {
                // could not find a populated tick within 256 bits, continue looking
                continue;
            }
            // we have found a non-empty tick that needs to be liquidated
            bytes32 tickHash = _tickHash(tick);
            uint256 length = positionsInTick[tickHash];
            totalLongPositions -= length;
            liquidated += length;
            totalExpo -= totalExpoByTick[tickHash];

            // Increment version to liquidate all ticks's positions
            unchecked {
                ++tickVersion[tick];
            }

            tickBitmap.flipTick(tick, tickSpacing);
        } while (i < maxIter);
        if (liquidated > 0) {
            if (tick < currentTick) {
                // all ticks above the current tick were liquidated
                maxInitializedTick = findMaxInitializedTick(currentTick);
            } else {
                // unsure if all ticks above the current tick were liquidated, but some were
                maxInitializedTick = findMaxInitializedTick(tick);
            }
        }
    }

    /// @dev Remove a long position from a tick.
    /// @param tick The tick.
    /// @param index The position index.
    /// @param amount The amount of the position.
    /// @param leverage The leverage of the position.
    function _removeLongPosition(int24 tick, uint256 index, uint128 amount, uint40 leverage) internal {
        uint256 removeExpo = (amount * leverage) / 10 ** LEVERAGE_DECIMALS;
        totalExpo -= removeExpo;
        bytes32 tickHash = _tickHash(tick);
        totalExpoByTick[tickHash] -= removeExpo;
        --positionsInTick[tickHash];
        // remove from positions list
        Position[] storage pos = longPositions[_tickHash(tick)];
        delete pos[index];
        if (positionsInTick[tickHash] == 0) {
            tickBitmap.flipTick(tick, tickSpacing);
        }
        totalLongPositions -= 1;
    }

    /* -------------------------------------------------------------------------- */
    /*                              Private Function                              */
    /* -------------------------------------------------------------------------- */

    /* ---------------------------- Perpetuals logics --------------------------- */

    /// @notice Commit a long entry.
    /// @param _amount The amount of asset to deposit.
    /// @param _liquidationPrice The desired liquidation price.
    function _openLong(uint96 _amount, uint128 _liquidationPrice) private returns (int24, uint256) {
        if (_amount == 0) revert ZeroAmount();

        uint256 balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        if (asset.balanceOf(address(this)) != balanceBefore + _amount) {
            revert IncompleteTransfer(asset.balanceOf(address(this)), balanceBefore + _amount);
        }

        uint40 _timestamp = uint40(block.timestamp);

        PriceInfo memory _currentPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value - _amount }(
            _timestamp, ProtocolAction.OpenPosition, abi.encode()
        );

        uint256 _desiredLeverage = getLeverage(_currentPrice.price, _liquidationPrice);

        if (_desiredLeverage < minLeverage) revert LeverageTooLow();
        if (_desiredLeverage > maxLeverage) revert LeverageTooHigh();

        Position memory _long = Position({
            amount: _amount,
            leverage: uint40(_desiredLeverage),
            validated: false,
            timestamp: _timestamp,
            isExit: false,
            user: msg.sender,
            startPrice: 0
        });

        return _validateLongEntry(_long, _currentPrice);
    }

    /// @notice Commit a long exit.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    function _closeLong(int24 _tick, uint256 _index, bytes calldata _currentOraclePriceData)
        private
        returns (int24, uint256)
    {
        Position memory _long = getLongPosition(_tick, _index);
        _long.isExit = true;

        PriceInfo memory _currentPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint40(block.timestamp), ProtocolAction.ClosePosition, _currentOraclePriceData
        );

        return _validateLongExit(_long, _currentPrice, _tick, _index);
    }

    /// @notice Validate a long position that has not benn validated yet.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @param _finalOraclePriceData The oracle data to retrive the final validated price.
    function _validateLong(int24 _tick, uint256 _index, bytes calldata _finalOraclePriceData) private {
        Position storage _storedLong = longPositions[_tickHash(_tick)][_index];
        Position memory _long = _storedLong;

        if (_long.user != msg.sender) revert AccessDenied();
        if (_long.validated) revert InvalidPendingPosition();

        PriceInfo memory _finalPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint128(block.timestamp), ProtocolAction.OpenPosition, _finalOraclePriceData
        );

        /// @dev Update storage
        /// We update the start price only
        /// The leverage has been calculated a the first tx, and should not be
        /// updated. The liquidation price will be updated according to he new
        /// price and the computed leverage.
        ///   E.g.
        ///     Tx1:
        ///       - Price: 1000
        ///       - liquidationPrice: 500
        ///       => leverage = 2
        ///     Tx2:
        ///       - Price: 2000
        ///       => liquidationPrice is now 1000
        ///       => leverage still 2
        _storedLong.startPrice = _finalPrice.price;
        _storedLong.validated = true;

        // TODO: gas opti !
        //       this reassignment probably read the whole position data to copy
        //       it in memory, but this is not necessary.
        _long = _storedLong;

        if (_long.isExit) {
            _validateLongExit(_long, _finalPrice, _tick, _index, false);
        } else {
            _validateLongEntry(_long, _finalPrice, false);
        }
    }

    /// @notice Commit a short entry.
    /// @param amount The amount of asset to deposit.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    function _deposit(uint128 amount, bytes calldata _currentOraclePriceData) private {
        if (amount == 0) revert ZeroAmount();

        uint256 balanceBefore = asset.balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount);
        if (asset.balanceOf(address(this)) != balanceBefore + amount) {
            revert IncompleteTransfer(asset.balanceOf(address(this)), balanceBefore + amount);
        }

        uint40 _timestamp = uint40(block.timestamp);

        PriceInfo memory _currentPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value - amount }(
            _timestamp, ProtocolAction.Deposit, _currentOraclePriceData
        );

        Position memory _short = Position({
            user: msg.sender,
            amount: amount,
            startPrice: _currentPrice.price,
            leverage: 0,
            validated: false,
            isExit: false,
            timestamp: _timestamp
        });

        pendingShortPositions[msg.sender] = _short;

        _validateShortEntry(_short, _currentPrice);
    }

    /// @notice Commit a short exit.
    /// @param amount The amount of USDN to burn.
    /// @param _currentOraclePriceData The oracle data to retrive the current price.
    function _withdraw(uint128 amount, bytes calldata _currentOraclePriceData) private {
        if (amount == 0) revert ZeroAmount();

        uint40 _timestamp = uint40(block.timestamp);

        PriceInfo memory _currentPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            _timestamp, ProtocolAction.Withdraw, _currentOraclePriceData
        );

        Position memory _short = Position({
            user: msg.sender,
            amount: amount,
            startPrice: _currentPrice.price,
            leverage: 0,
            validated: false,
            isExit: true,
            timestamp: _timestamp
        });

        pendingShortPositions[msg.sender] = _short;

        _validateShortExit(_short, _currentPrice);
    }

    /// @notice Validate a short position that has not benn validated yet.
    /// @param _finalOraclePriceData The oracle data to retrive the final validated price.
    function _validateShort(bytes calldata _finalOraclePriceData) private {
        Position memory _short = pendingShortPositions[msg.sender];

        if (_short.validated) revert InvalidPendingPosition();

        PriceInfo memory _finalPrice = oracleMiddleware.parseAndValidatePrice{ value: msg.value }(
            uint128(block.timestamp), ProtocolAction.Withdraw, _finalOraclePriceData
        );

        // Update the position price
        _short.startPrice = _finalPrice.price;

        // Update storage
        delete pendingShortPositions[msg.sender];

        if (_short.isExit) {
            _validateShortExit(_short, _finalPrice);
        } else {
            _validateShortEntry(_short, _finalPrice);
        }
    }

    function _validatePreviousActionPrice(bytes calldata previousPriceData) private {
        // TODO: implement
        //       - Check if it is possible
        //       - Validate last action
    }

    /* ------------------------------ Short logics ------------------------------ */

    /// @dev Validate a short entry.
    /// @param _short The short position.
    /// @param _currentPrice The price corresponding to the position timestamp.
    function _validateShortEntry(Position memory _short, PriceInfo memory _currentPrice) private {
        // Revert if position is empty
        if (_short.user == address(0)) return;
        // Revert if position is not an entry position
        if (_short.isExit) revert InvalidPendingPosition();
        // Revert if position is not a short position
        if (_short.leverage > 0) revert InvalidPendingPosition();

        _applyPnlAndFunding(_currentPrice.price, _currentPrice.timestamp);
        uint256 usdnToMint = _calcMintUsdp(_short.amount, _currentPrice.price);
        usdn.mint(msg.sender, usdnToMint);

        balanceShort += _short.amount;
    }

    /// @dev Validate a short exit.
    /// @param _short The short position.
    /// @param _currentPrice The price corresponding to the position timestamp.
    function _validateShortExit(Position memory _short, PriceInfo memory _currentPrice) private {
        uint256 _totalSupply = usdn.totalSupply();

        //FIXME: what is an appropriate value here?
        if (_totalSupply - _short.amount < 1000) {
            revert MinTotalSupply(); // totalSupply cannot fall too low
        }

        _applyPnlAndFunding(_currentPrice.price, _currentPrice.timestamp);

        int256 available = shortAssetAvailable(_currentPrice.price);
        if (available < 0) {
            available = 0;
        }
        // assetToTransfer = amountUsdp * usdnPrice / assetPrice = amountUsdp * assetAvailable / totalSupply
        uint256 assetToTransfer = (_short.amount * uint256(available)) / _totalSupply;
        balanceShort -= assetToTransfer;
        usdn.burnFrom(msg.sender, _short.amount); // checks that balance is sufficient
        uint256 balanceBefore = asset.balanceOf(address(this));
        if (assetToTransfer > 0) {
            asset.safeTransfer(msg.sender, assetToTransfer);
            if (asset.balanceOf(address(this)) != balanceBefore - assetToTransfer) {
                revert IncompleteTransfer(asset.balanceOf(address(this)), balanceBefore - assetToTransfer);
            }
        }
    }

    /* ------------------------------- Long logics ------------------------------ */

    /// @dev Validate a long entry.
    /// @param _long The long position.
    /// @param _currentPrice The price corresponding to the position timestamp.
    function _validateLongEntry(Position memory _long, PriceInfo memory _currentPrice)
        private
        returns (int24 tick, uint256 index)
    {
        return _validateLongEntry(_long, _currentPrice, true);
    }

    /// @dev Validate a long entry.
    /// @param _long The long position.
    /// @param _currentPrice The price corresponding to the position timestamp.
    /// @param _firstTime Whether this is the first time the position is treated.
    function _validateLongEntry(Position memory _long, PriceInfo memory _currentPrice, bool _firstTime)
        private
        returns (int24 tick, uint256 index)
    {
        // Revert if position is empty
        if (_long.user == address(0)) return (0, 0);
        // Revert if position is not an entry position
        if (_long.isExit) revert InvalidPendingPosition();
        // Revert if position is not a long position
        if (_long.leverage < minLeverage) {
            revert InvalidPendingPosition();
        }

        _applyPnlAndFunding(_currentPrice.price, _currentPrice.timestamp);

        uint128 liquidationPrice = getLiquidationPrice(_currentPrice.price, _long.leverage);
        tick = TickMath.getTickAtPrice(TickMath.fromDecimal(int256(uint256(liquidationPrice)), priceFeedDecimals));
        tick = (tick / tickSpacing) * tickSpacing;
        // calculate real leverage from tick and corresponding price
        liquidationPrice = uint128(uint256(TickMath.toDecimal(TickMath.getPriceAtTick(tick), priceFeedDecimals)));
        uint40 leverage = getLeverage(_currentPrice.price, liquidationPrice);

        if (_firstTime) balanceLong += _long.amount;

        uint256 addExpo = (_long.amount * leverage) / 10 ** LEVERAGE_DECIMALS;
        totalExpo += addExpo;
        bytes32 tickHash = _tickHash(tick);
        totalExpoByTick[tickHash] += addExpo;

        Position memory long = Position({
            user: msg.sender,
            amount: _long.amount,
            startPrice: _currentPrice.price,
            leverage: leverage,
            validated: _long.validated,
            isExit: false,
            timestamp: uint40(block.timestamp)
        });
        Position[] storage pos = longPositions[tickHash];
        if (positionsInTick[tickHash] == 0) {
            // first position in this tick
            tickBitmap.flipTick(tick, tickSpacing);
        }
        if (tick > maxInitializedTick) {
            maxInitializedTick = tick;
        }
        pos.push(long);
        index = pos.length - 1;
        totalLongPositions += 1;
        ++positionsInTick[tickHash];
    }

    /// @dev Validate a long exit.
    /// @param _long The long position.
    /// @param _currentPrice The price corresponding to the position timestamp.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function _validateLongExit(Position memory _long, PriceInfo memory _currentPrice, int24 _tick, uint256 _index)
        private
        returns (int24 tick, uint256 index)
    {
        return _validateLongExit(_long, _currentPrice, _tick, _index, true);
    }

    /// @dev Validate a long exit.
    /// @param _long The long position.
    /// @param _currentPrice The price corresponding to the position timestamp.
    /// @param _tick The tick containing the position.
    /// @param _index The position index in the tick.
    /// @param _firstTime Whether this is the first time the position is treated.
    /// @return tick The tick containing the position.
    /// @return index The position index in the tick.
    function _validateLongExit(
        Position memory _long,
        PriceInfo memory _currentPrice,
        int24 _tick,
        uint256 _index,
        bool _firstTime
    ) private returns (int24 tick, uint256 index) {
        // Revert if position is empty
        if (_long.user == address(0)) revert NoPendingPosition();
        // Revert if position is not an exit position
        if (!_long.isExit) revert InvalidPendingPosition();
        // Revert if position is not a long position
        if (_long.leverage < minLeverage) revert InvalidPendingPosition();

        tick = _tick;
        index = _index;

        if (_long.user != msg.sender) {
            revert AccessDenied();
        }

        _applyPnlAndFunding(_currentPrice.price, _currentPrice.timestamp);

        if (_currentPrice.price <= getLiquidationPrice(_long.startPrice, _long.leverage)) {
            _removeLongPosition(tick, index, _long.amount, _long.leverage);
            return (0, 0);
        }

        int256 available = longAssetAvailable(_currentPrice.price);
        if (available < 0) {
            available = 0;
        }

        int256 value = positionValue(_currentPrice.price, _long.startPrice, _long.amount, _long.leverage);
        if (value < 0) {
            value = 0;
        }
        // FIXME: this is probably wrong
        uint256 assetToTransfer = uint256(value * available) / totalExpo;

        _removeLongPosition(tick, index, _long.amount, _long.leverage);

        uint256 balanceBefore = asset.balanceOf(address(this));
        if (assetToTransfer > 0 && !_firstTime) {
            balanceLong -= assetToTransfer;
            asset.safeTransfer(msg.sender, assetToTransfer);
            if (asset.balanceOf(address(this)) != balanceBefore - assetToTransfer) {
                revert IncompleteTransfer(asset.balanceOf(address(this)), balanceBefore - assetToTransfer);
            }
        }
    }
}
