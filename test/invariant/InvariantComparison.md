# Invariant Testing: Foundry vs Medusa

## Conceptual Architecture

| Aspect | Foundry | Medusa |
|--------|---------|--------|
| **Core Approach** | Stateless property testing with random function calls | Stateful invariant checking with coverage-guided fuzzing |
| **Execution Model** | Random fuzzing with shrinking | Coverage-guided fuzzing with mutation algorithms |
| **Test Structure** | Public functions prefixed with `invariant_` | Properties defined in separate contracts |
| **State Tracking** | Manual (must be implemented by user) | Built-in before/after state management |
| **Sequence Generation** | Random selection from targeted functions | Intelligent sequence generation based on coverage |

## Stateless vs Stateful Invariant Testing

### Stateless Property Testing (Foundry's Approach)

Stateless property testing focuses on checking invariants at a single point in time without explicitly tracking how the system got to that state. In this approach:

- Each invariant check is independent of previous system states
- The test doesn't explicitly store or compare state before and after operations
- Assertions verify that properties hold true at the moment they are checked
- System history and transitions are not explicitly modeled

Think of stateless testing like taking a snapshot of your system and verifying that certain rules hold true in that snapshot, regardless of how the system arrived at that point.

### Stateful Invariant Checking (Medusa's Approach)

Stateful invariant checking explicitly models and tracks system state changes, comparing properties before and after operations. In this approach:

- The testing framework captures system state before operations
- It runs sequences of operations that modify the system
- It captures the resulting state after operations
- Invariants compare the before and after states to verify properties about transitions

Think of stateful testing like filming a video of your system changing over time, then analyzing how it changed from one frame to the next to ensure the transitions followed all the rules.

### Key Differences

| Aspect | Stateless (Foundry) | Stateful (Medusa) |
|--------|---------|--------|
| State Tracking | Implicit or manual | Explicit and built-in |
| Focus | Point-in-time properties | Transition properties |
| Implementation Complexity | Simpler to implement | More complex but more powerful |
| Bug Detection | Good for state invariants | Better for transition bugs |

## Testing Flow

### Foundry

1. **Setup Phase**

- Register target contracts via `targetContract()`
- Register target functions via `targetSelector()`
- Register valid senders via `targetSender()`
- Configure handler contracts via `targetInterface()`

2. **Execution Phase**

- For each fuzzing run:
  - Generate random sequence of function calls
  - Execute calls with random inputs
  - After each sequence (or call), check invariants
  - If invariant fails, shrink to minimal failing case

3. **Verification Phase**

- Call all functions that start with `invariant_`
- Report pass/fail status

### Medusa

1. **Setup Phase**

- Configure corpus directory and test targets
- Define libraries and their addresses
- Set up campaign parameters (workers, timeout, etc.)

2. **Execution Phase**

- Record initial state before function calls
- Execute sequences of function calls with mutated inputs
- Capture coverage information to guide future inputs
- Record final state after calls
- Check defined invariants between states

3. **Verification Phase**

- Evaluate properties defined in contracts like `Properties_WITHI`
- Generate coverage reports and failure cases

## Implementation Differences

| Feature | Foundry | Medusa |
|---------|---------|--------|
| **State Management** | User-implemented via mappings and storage | Automated via `_before()` and `_after()` functions |
| **Library Handling** | Uses `--libraries` flag or `foundry.toml` | Uses predeployed address mapping in config |
| **Assertion Framework** | Native Forge assertions (`assertEq`, etc.) | Custom assertion library (e.g., `fl.eq`) |
| **Failure Handling** | Shrinks to minimal counterexample | Records complete call sequence |
| **Coverage Analysis** | Basic coverage reporting | Detailed coverage with branch information |
| **Corpus Management** | Limited | Persistent corpus for incremental fuzzing |
