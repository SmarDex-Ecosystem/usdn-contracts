#!/usr/bin/env bash

set -ux

# Store current state of files for restoration
mkdir -p .temp_backup
cp -r src/UsdnProtocol/libraries/ .temp_backup/UsdnProtocol_libraries/
cp -r src/libraries/ .temp_backup/libraries/

j=$((0x10)); 
SOLIDITY_FILES=$(find src/UsdnProtocol/libraries/ src/libraries/ -type f | sed 's/.*\///' | sed 's/\.sol//')

rm COMPILE_LIBRARIES.txt || true
rm DEPLOY_CONTRACTS.txt || true

while read i; do 
    echo "($i,$(printf "0x%x" $j))" >> COMPILE_LIBRARIES.txt
    echo "[$(printf "\"0x%x\"" $j), \"$i\"]" >> DEPLOY_CONTRACTS.txt
    j=$((j+1))
done <<< "$SOLIDITY_FILES"

COMPILE_LIBRARIES=$(cat COMPILE_LIBRARIES.txt | paste -sd, -)
DEPLOY_CONTRACTS=$(cat DEPLOY_CONTRACTS.txt | paste -sd, -)

echo $COMPILE_LIBRARIES
echo $DEPLOY_CONTRACTS

# sed -i "s/cryticArgs.*/cryticArgs: [\"--compile-libraries=$COMPILE_LIBRARIES\"]/" echidna.yaml
# sed -i "s/\"args\".*/\"args\": [\"--compile-libraries=$COMPILE_LIBRARIES\"]/" medusa.json
# sed -i "s/deployContracts.*/deployContracts: [$DEPLOY_CONTRACTS]/g" echidna.yaml

# More comprehensive replacements with better regex patterns
find src/UsdnProtocol/libraries/ src/libraries/ -type f -name "*.sol" -exec sed -i -E 's/\bpublic\b/internal/g' {} \;
find src/UsdnProtocol/libraries/ src/libraries/ -type f -name "*.sol" -exec sed -i -E 's/\bexternal\b/internal/g' {} \;
find src/UsdnProtocol/libraries/ src/libraries/ -type f -name "*.sol" -exec sed -i -E 's/\bcalldata\b/memory/g' {} \;

rm COMPILE_LIBRARIES.txt || true
rm DEPLOY_CONTRACTS.txt || true

# Run Medusa fuzzing
echo "Running Medusa fuzzing..."
medusa fuzz --config ./medusa.json

# # Restore original files
# echo "Restoring original library files..."
# cp -r .temp_backup/UsdnProtocol_libraries/* src/UsdnProtocol/
# cp -r .temp_backup/libraries/* src/
# rm -rf .temp_backup

echo "Process complete."