// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import { StdStyle, console, console2 } from "forge-std/Test.sol";

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { HugeUint } from "@smardex-solidity-libraries-1/HugeUint.sol";

import { FuzzRebalancer } from "./FuzzRebalancer.sol";
import { FuzzUsdnProtocolActions } from "./FuzzUsdnProtocolActions.sol";
import { FuzzUsdnProtocolVault } from "./FuzzUsdnProtocolVault.sol";

import { IUsdnProtocolTypes as Types } from "../../../src/interfaces/UsdnProtocol/IUsdnProtocolTypes.sol";
import { SignedMath } from "../../src/libraries/SignedMath.sol";
import { TickMath } from "../../src/libraries/TickMath.sol";

// @todo multiple tests fail on [panic: arithmetic underflow/overflow] in stack trace (fuzz_guided_liquidateHighestTick,
// fuzz_initiateClosePosition) coming from the guardian perimetersec lib of fl.clamp()
contract FuzzGuided is FuzzUsdnProtocolVault, FuzzUsdnProtocolActions, FuzzRebalancer {
    using SignedMath for int256;
    using HugeUint for HugeUint.Uint512;

    constructor() payable {
        vm.warp(1_524_785_992); //medusa starting time

        setup(address(this));
    }

    function fuzz_guided_addLP() public {
        require(!LPAdded);
        fuzz_guided_depositFlow(1, 75e18);

        LPAdded = true;
    }

    function fuzz_guided_open10Positions() public {
        setActor(USER3);
        fuzz_initiateDepositAssets(1000e18);
        setActor(USER3);
        fuzz_validateDepositAssets();

        fuzz_guided_depositFlow(1, 20e18);
        for (uint256 i; i < 5; i++) {
            fuzz_guided_openPosition(1);
        }

        fuzz_guided_depositFlow(2, 20e18);
        for (uint256 i; i < 5; i++) {
            fuzz_guided_openPosition(2);
        }
    }

    function fuzz_guided_liquidateAndRebalance() public {
        setActor(USER1);
        fuzz_initiateDepositAssets(1000e18);
        fuzz_validateDepositAssets();

        setActor(USER2);
        fuzz_guided_depositFlow(1, 75e18);

        setActor(USER2);
        fuzz_guided_openPosition(1);

        setActor(USER2);
        fuzz_guided_liquidateHighestTick();

        setActor(USER1);
        fuzz_initiateClosePositioninRebalancer(1e17);
    }

    function fuzz_guided_liquidateHighestTick() public {
        uint256 newPrice = Math.mulDiv(approximateLiqPriceForHiPopTick(createProtocolPrice()), 1e18, 115e16);

        int256 oraclePrice = int256(newPrice / 1e18);
        setPythPrice(oraclePrice);
        setChainlinkPrice(oraclePrice);

        // do deposit flow with super small amount to liquidate inside a call
        fuzz_initiateDeposit(100, 1);
    }

    function approximateLiqPriceForHiPopTick(uint256 ourPrice) internal returns (uint128 changedPrice) {
        int24 highestTick = usdnProtocol.getHighestPopulatedTick();

        Types.ApplyPnlAndFundingData memory temporaryData =
            usdnProtocol.i_applyPnlAndFundingStateless(uint128(ourPrice), uint128(block.timestamp));

        uint256 longTradingExpo = usdnProtocol.getLongTradingExpo(uint128(temporaryData.lastPrice));

        HugeUint.Uint512 memory accumulator = usdnProtocol.getLiqMultiplierAccumulator();

        uint256 initialUnadjustedPrice =
            usdnProtocol.i_unadjustPrice(temporaryData.lastPrice, temporaryData.lastPrice, longTradingExpo, accumulator);

        uint256 unadjustedPrice = initialUnadjustedPrice;
        int24 currentTick = TickMath.getTickAtPrice(unadjustedPrice);

        uint256 iterationCount = 0;
        uint256 previousUnadjustedPrice = 0;

        while ((currentTick > highestTick) || (currentTick < highestTick - (100))) {
            previousUnadjustedPrice = unadjustedPrice;

            if (currentTick > highestTick) {
                ourPrice = ourPrice - 11e18;
            } else {
                ourPrice = ourPrice + 11e18;
            }

            // Update prices and ticks after price change
            temporaryData = usdnProtocol.i_applyPnlAndFundingStateless(uint128(ourPrice), uint128(block.timestamp));

            longTradingExpo = usdnProtocol.getLongTradingExpo(uint128(temporaryData.lastPrice));

            unadjustedPrice = usdnProtocol.i_unadjustPrice(
                temporaryData.lastPrice, temporaryData.lastPrice, longTradingExpo, accumulator
            );

            currentTick = TickMath.getTickAtPrice(unadjustedPrice);

            // Verify unadjusted price is decreasing when we want it to
            if (currentTick > highestTick) {
                require(unadjustedPrice < previousUnadjustedPrice, "Unadjusted price not decreasing when it should");
            }

            iterationCount++;
            require(iterationCount < 1000, "Too many iterations");
        }

        changedPrice = uint128(ourPrice);

        return changedPrice;
    }

    function fuzz_guided_makeBigDeposit(uint8 seed) public {
        if (seed % 2 == 0) {
            fuzz_guided_depositFlow(seed, 25e18);
        } else if (seed % 3 == 0) {
            fuzz_guided_depositFlow(seed, 50e18);
        } else {
            fuzz_guided_depositFlow(seed, 75e18);
        }
    }

    function fuzz_guided_openBigPosition(uint8 seed) public {
        if (seed % 2 == 0) {
            fuzz_guided_openPosition(seed);
        } else if (seed % 3 == 0) {
            fuzz_guided_openPosition(seed);
        } else {
            fuzz_guided_openPosition(seed);
        }
    }

    function fuzz_guided_depositFlow(uint8 seed, uint256 amount) public {
        setActor(getRandomUser(seed)); //same initiator + validator
        fuzz_initiateDeposit(amount, 1);

        setActor(getRandomUser(seed));
        fuzz_validateDeposit();
    }

    function fuzz_guided_withdrawalFlow(uint8 seed, uint152 amount) public {
        setActor(getRandomUser(seed));
        fuzz_initiateWithdrawal(amount);

        setActor(getRandomUser(seed));
        fuzz_validateWithdrawal();
    }

    function fuzz_guided_rebalancerDepositFlow(uint8 seed, uint256 amount) public {
        setActor(getRandomUser(seed)); //same initiator + validator\
        fuzz_initiateDepositAssets(uint88(amount));

        setActor(getRandomUser(seed));
        fuzz_validateDepositAssets();
    }

    function fuzz_guided_openPosition(uint8 seed) public {
        setActor(getRandomUser(seed));
        fuzz_initiateOpenPosition(uint256(seed) * 1e18, 15e20);

        setActor(getRandomUser(seed));
        fuzz_validateOpenPosition();
    }

    function _consoleLogKeyParams() internal view {
        console.log("");
        console.log(StdStyle.green("PROTOCOL KEY PARAMETERS"));
        console.log(StdStyle.green("-----------------------------------------------------------"));
        int256 vaultExpo = int256(usdnProtocol.getBalanceVault()).safeAdd(usdnProtocol.getPendingBalanceVault());
        int256 longExpo = int256(usdnProtocol.getTotalExpo()).safeSub(int256(usdnProtocol.getBalanceLong()));
        if (longExpo == 0) {
            return;
        }
        int256 imbalanceBps;
        if (vaultExpo >= longExpo) {
            imbalanceBps = vaultExpo.safeSub(longExpo).safeMul(int256(10_000)).safeDiv(longExpo);
            console.log(
                StdStyle.green("ImbalanceBps ................................ %s vault side higher"),
                vm.toString(imbalanceBps)
            );
        } else {
            imbalanceBps = longExpo.safeSub(vaultExpo).safeMul(int256(10_000)).safeDiv(vaultExpo);
            console.log(
                StdStyle.green("ImbalanceBps ................................ %s long side higher"),
                vm.toString(imbalanceBps)
            );
        }
        console.log(StdStyle.green("VaultExpo ................................... %s"), vm.toString(vaultExpo));
        // Long exposure -> s._totalExpo - s._balanceLong
        console.log(StdStyle.green("LongExpo .................................... %s"), vm.toString(longExpo));
        // This variable accurately tracks the wstETH amount in the vault
        console.log(
            StdStyle.yellow("usdnProtocol.getBalanceVault() .................. %s"),
            vm.toString(usdnProtocol.getBalanceVault())
        );
        // This variable accurately tracks the wstETH amount which was provided as collateral on the long side
        console.log(
            StdStyle.yellow("usdnProtocol.getBalanceLong() ................... %s"),
            vm.toString(usdnProtocol.getBalanceLong())
        );
        console.log(
            StdStyle.yellow("usdnProtocol.getMinLeverage() ................... %s"),
            vm.toString(usdnProtocol.getMinLeverage())
        );
        console.log(
            StdStyle.yellow("usdnProtocol.getMaxLeverage() ................... %s"),
            vm.toString(usdnProtocol.getMaxLeverage())
        );
        console.log(
            StdStyle.yellow("usdnProtocol.getLastPrice() ..................... %s"),
            vm.toString(usdnProtocol.getLastPrice())
        );
        console.log(
            StdStyle.yellow("usdnProtocol.getLastUpdateTimestamp() ........... %s"),
            vm.toString(usdnProtocol.getLastUpdateTimestamp())
        );
        console.log(
            StdStyle.yellow("usdnProtocol.getPendingBalanceVault() ........... %s"),
            vm.toString(usdnProtocol.getPendingBalanceVault())
        );

        console.log(
            StdStyle.yellow("usdnProtocol.getEMA() ........................... %s"), vm.toString(usdnProtocol.getEMA())
        );
        console.log(
            StdStyle.yellow("usdnProtocol.getTotalExpo() ..................... %s"),
            vm.toString(usdnProtocol.getTotalExpo())
        );
        HugeUint.Uint512 memory hug = usdnProtocol.getLiqMultiplierAccumulator();
        console.log(StdStyle.yellow("usdnProtocol.getLiqMultiplierAccumulator().hi ... %s"), vm.toString(hug.hi));
        console.log(StdStyle.yellow("usdnProtocol.getLiqMultiplierAccumulator().lo ... %s"), vm.toString(hug.lo));
        console.log(
            StdStyle.yellow("usdnProtocol.getHighestPopulatedTick() .......... %s"),
            vm.toString(usdnProtocol.getHighestPopulatedTick())
        );
        console.log(
            StdStyle.yellow("liquidation price for tick(%s) ........... %s"),
            vm.toString(usdnProtocol.getHighestPopulatedTick()),
            TickMath.getPriceAtTick(usdnProtocol.getHighestPopulatedTick())
        );
        console.log(
            StdStyle.yellow("usdnProtocol.getTotalLongPositions() ............ %s"),
            vm.toString(usdnProtocol.getTotalLongPositions())
        );
        console.log(StdStyle.green("-----------------------------------------------------------"));
        console.log("");
    }

    function printProtocolData(string memory action) internal view {
        uint256 totalExpo = usdnProtocol.getTotalExpo();
        uint256 balanceVault = usdnProtocol.getBalanceVault();
        int256 pendingBalanceVault = usdnProtocol.getPendingBalanceVault();
        uint256 balanceLong = usdnProtocol.getBalanceLong();
        uint128 lastPrice = usdnProtocol.getLastPrice();
        (int256 fundingAsset, int256 fundingPerDay) =
            usdnProtocol.i_fundingAsset(uint128(block.timestamp), usdnProtocol.getEMA());
        int24 highestPopulatedTick = usdnProtocol.getHighestPopulatedTick();
        HugeUint.Uint512 memory accumulator = usdnProtocol.getLiqMultiplierAccumulator();
        uint256 multiplier =
            usdnProtocol.i_calcFixedPrecisionMultiplier(lastPrice, totalExpo - balanceLong, accumulator);

        Types.TickData memory tickData = usdnProtocol.getTickData(highestPopulatedTick);

        int24 nextTick;
        Types.TickData memory tickData2;

        console2.log("\n=> Action: %s", action);
        console2.log("                                                            ");
        console2.log(" ========================================================== ");
        console2.log("                   CURRENT PROTOCOL STATE                   ");
        console2.log(" ========================================================== ");
        console2.log("                                                            ");

        console2.log("  balanceVault:         %s", balanceVault);
        console2.log("  pendingBalanceVault:         %s", pendingBalanceVault);

        console2.log("  fundingAsset:         %s", fundingAsset);
        console2.log("  fundingPerDay:         %s", fundingPerDay);
        console2.log("  multiplier:         %s", multiplier);

        console2.log("  totalPositions:         %s", usdnProtocol.getTotalLongPositions());
        console2.log("  currentTick:            %s", TickMath.getTickAtPrice(uint256(lastPrice)));

        console2.log("  lastUpdate:             %s", usdnProtocol.getLastUpdateTimestamp());

        console2.log("");
        console2.log("  = Active Ticks = \n");
        console2.log("      Tick: ", highestPopulatedTick);

        console2.log("        positions:  %s", tickData.totalPos);
        console2.log("        liqPenalty: %s", tickData.liquidationPenalty);
        console2.log("        version:    %s", usdnProtocol.getTickVersion(highestPopulatedTick));
        console2.log("");
        uint256 interactions;
        while (highestPopulatedTick != 0) {
            for (int24 i = highestPopulatedTick - 100; i > highestPopulatedTick - 100_000; i -= 100) {
                interactions = interactions + 1;
                tickData2 = usdnProtocol.getTickData(i);
                if (tickData2.totalPos > 0) {
                    nextTick = i;
                    highestPopulatedTick = nextTick;
                    console2.log("      Tick: ", nextTick);

                    console2.log("        positions:  %s", tickData2.totalPos);
                    console2.log("        liqPenalty: %s", tickData2.liquidationPenalty);
                    console2.log("        version:    %s", usdnProtocol.getTickVersion(nextTick));
                    interactions = 0;
                    break;
                }
                if (interactions == 2000) {
                    highestPopulatedTick = 0;
                    break;
                }
            }
        }
        console2.log("");
        console2.log(" ========================================================== ");
        console2.log("                                                            ");
    }
}
