#!/usr/bin/env bash
set -ux

# Store original files as backup
mkdir -p .temp_backup
cp -r src/UsdnProtocol/libraries/ .temp_backup/UsdnProtocol_libraries/
cp -r src/libraries/ .temp_backup/libraries/

# Change for fuzzing
find src/UsdnProtocol/libraries/ src/libraries/ -type f -name "*.sol" -exec sed -i -E 's/\bpublic\b/internal/g' {} \;
find src/UsdnProtocol/libraries/ src/libraries/ -type f -name "*.sol" -exec sed -i -E 's/\bexternal\b/internal/g' {} \;
find src/UsdnProtocol/libraries/ src/libraries/ -type f -name "*.sol" -exec sed -i -E 's/\bcalldata\b/memory/g' {} \;

# Run Medusa fuzzing
echo "Running Medusa fuzzing..."
medusa fuzz --config ./medusa.json

# Restore from backup instead of trying to reverse with sed
cp -r .temp_backup/UsdnProtocol_libraries/* src/UsdnProtocol/libraries/
cp -r .temp_backup/libraries/* src/libraries/
rm -rf .temp_backup

echo "Process complete."