## Reproducing Foundry Test Sequences from Fuzzing Results

This guide explains how to generate a reproducible test sequence from the fuzzing corpus using Foundry.

### Step 1: Select the Correct Sequence

- Locate the `test_results` folder within the fuzzing corpus.
- Identify the json sequence file that corresponds to the failure logged during testing.

### Step 2: Prepare the Sequence File

- Copy the contents of the chosen sequence file.
- Save the contents into a new file at `test/fuzzing/Sequences.json`.

### Step 3: Generate the Test Sequence

Run the following command to generate the test sequence:

```bash
npx tsx script/generateSequence.ts
```

### Step 4: Run your Foundry Test

Run the Foundry test with the stack traces:

```bash
forge test --mt test_sequence -vvvv
```