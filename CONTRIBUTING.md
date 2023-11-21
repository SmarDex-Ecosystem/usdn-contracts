# Contributing

In general, please follow the [Foundry Best Practices](https://book.getfoundry.sh/tutorials/best-practices) guidelines
unless specified otherwise here.

## Imports

In solidity files, imports should always be relative to the **root of the repo**. Do not use relative imports.

Imports should be sorted in the following way:

- First block with `forge-std` imports
- Second block with external dependencies (e.g. `@openzeppelin`)
- Third block with `test` imports
- Fourth block with `script` imports
- Fifth block with `src` imports

Example (note, there is no `script` import in the example):

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { console2 } from "forge-std/Test.sol";
import { StdStorage } from "forge-std/Script.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { FixedPointMathLib } from "solady/src/utils/FixedPointMathLib.sol";

import { TickMathFixture } from "test/unit/TickMath/utils/Fixtures.sol";

import { TickMath } from "src/libraries/TickMath.sol";
```

## Errors

Since custom errors are not namespaced to a given contract, it could be difficult to identify where the error originates
from. As such, all errors should be prefixed with the name of the contract that defines them. For interfaces, the errors
are prefixed with the name of the interface.

Examples: `UsdnInvalidMultiplier()`, `TickMathInvalidTick()`.

## Testing conventions

When writing or modifying tests, please follow the following conventions:

### Hierarchy

All tests are located inside the `test` folder.

Inside that folder, tests are organized in these sub-folders:

- `unit`: for unit tests which use a single contract
- `integration`: for integration tests where multiple contracts interact
- `utils`: non-test utilities that are useful for any kind of test

### Unit tests

Inside the `unit` folder, each tested contract has its own sub-directory with the same name as the contract.

Inside of the `ContractName` folders, there can be a `utils` folder with utilities specific to testing that contract.

### Fixtures

Test fixtures should be located inside the `[unit/integration]/ContractName/utils/Fixtures.sol` file. The name of the
fixture contract should end with `Fixture` and extend `test/utils/Fixtures.sol:BaseFixture`.

Each fixture can implement the `setUp()` function to perform its setup. Test contracts which implement the fixture can
override that method with their own `function setUp() public override { super.setUp(); }` which should call the parent
setup function.

### Test files

Inside the contract sub-folder, test files should be named `ContractName.function.t.sol` where `function` is the name
of the function being tested. For very small functions, they can be grouped in a single file/contract named accordingly.

The contract name inside that file should be `TestContractNameMethod`.

Fuzzing tests should be separated in their own file and contract, potentially breaking it down into several files by
fuzzed function if necessary.

In general, favor multiple small contracts over one big monolith, so that solidity compilation can be better
parallelized.

### Test names

Tests are functions with a `public` visibility, that start with the keyword `test`.

Positive tests are named `test_somethingHappens()`.

Tests that should revert are named `test_RevertWhen_somethingHappens()`.

Fuzzing tests take one or more parameters which will be fuzzed and should be named `testFuzz_something(uint256 p)`.

### NatSpec

For tests, a special set of NatSpec keywords are used to describe the test context and content, similar to what
[Gherkin](https://cucumber.io/docs/gherkin/reference/) does.

The main keywords of Gherkin can be used as `@custom:` NatSpec entries:

- `@custom:feature`
- `@custom:background`
- `@custom:scenario`
- `@custom:given`
- `@custom:when`
- `@custom:then`
- `@custom:and`
- `@custom:but`

Here is an example `MyToken.transfer.t.sol` file implementing those:

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

// imports

/**
 * @custom:feature Test the `transfer` function of some ERC-20 token
 * @custom:background Given the token is not paused
 */
contract TestMyTokenTransfer is MyTokenFixture {
    /**
     * @custom:scenario A user transfers tokens normally
     * @custom:given The user has 100 tokens
     * @custom:when The user tries to transfer 50 tokens to the contract
     * @custom:then The `Transfer` event should be emitted with the same contract address and amount
     * @custom:and The balance of the user should decrease by 50 tokens
     * @custom:and The balance of the contract should increase by 50 tokens
     */
    function test_transfer() public {
        // ...
    }
}
```
