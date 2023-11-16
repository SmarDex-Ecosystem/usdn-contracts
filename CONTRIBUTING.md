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

### NatSpec

For tests, a special set of NatSpec keywords are used to describe the test context and content.
