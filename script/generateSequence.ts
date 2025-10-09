import { writeFileSync } from 'node:fs';
import  * as sequences from '../test/fuzzing/Sequences.json';

const startContract = `
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { FuzzGuided } from "./FuzzGuided.sol";

contract PhilippeTestSequence is FuzzGuided {
    function test_sequence() public {
\n`;


const endContract = `
    \n}

    function _setChain(uint256 blockNumberDelay, uint256 blockTimestampDelay) internal {
       vm.roll(block.number + blockNumberDelay);
       vm.warp(block.timestamp + blockTimestampDelay);
    }
}
`

let testSequence = startContract;

for(const sequence of sequences) {
    // uncomment the following 2 lines to handle the chain state
    // const chainSetup = `\n _setChain(${sequence.blockNumberDelay}, ${sequence.blockTimestampDelay}); \n`;
    // testSequence += chainSetup

    let functionCall = "";

    if(sequence.call.dataAbiValues.methodSignature.startsWith("fuzz_")) {
        let inputs = "";
        let valuesCount = 0;
        for(const inputValue of sequence.call.dataAbiValues.inputValues) {
            if(valuesCount > 0) {
                inputs += ", ";
            }

            inputs += inputValue.replace('"', "");
            valuesCount += 1;
        }
        functionCall = `${sequence.call.dataAbiValues.methodSignature.split("(")[0]}(${inputs.replace('"', "")}); \n`;
    }

    if(functionCall !== "") {
        testSequence += functionCall;
    }
}


testSequence += endContract;

writeFileSync("test/fuzzing/Sequences.t.sol", testSequence);

