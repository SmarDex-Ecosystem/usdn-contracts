// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { console } from "forge-std/Test.sol";

import { ReproducersBase } from "./ReproducersBase.sol";

contract CurrentReproducers is ReproducersBase {
    function test_replay() public {
        try this.pythPrice() { } catch { }

        try this.fuzz_initiateDepositAssets(4_277_692) { } catch { }

        try this.fuzz_initiateWithdrawal(4_511_420_339_053_028_840_618_221_102_773_018_654_233_170_735) { } catch { }

        try this.fuzz_guided_openPosition(46, 1_524_785_992) { } catch { }

        try this.fuzz_guided_depositFlow(169, 1_524_785_992) { } catch { }

        try this.targetSelectors() { } catch { }

        try this.targetInterfaces() { } catch { }

        try this.fuzz_validateWithdrawal() { } catch { }

        try this.fuzz_initiateWithdrawal(2_636_275_715_593_074_513_976_898_623_121_982_704_534_706_215) { } catch { }

        try this.fuzz_initiateOpenPosition(1_524_785_992, 1) { } catch { }

        try this.targetArtifacts() { } catch { }

        try this.fuzz_guided_liquidateHighestTick() { } catch { }

        try this.fuzz_validateDepositAssets() { } catch { }

        try this.targetArtifactSelectors() { } catch { }

        try this.fuzz_validateActionablePendingActions(4_370_000) { } catch { }

        try this.fuzz_guided_depositFlow(
            6, 115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457_584_007_913_129_639_934
        ) { } catch { }

        try this.fuzz_validateDepositAssets() { } catch { }

        try this.excludeContracts() { } catch { }

        try this.targetInterfaces() { } catch { }

        try this.failed() { } catch { }

        try this.fuzz_guided_withdrawalFlow(134, 1_524_785_991) { } catch { }

        fuzz_guided_addLP();

        console.log("HERE!");
    }
}
