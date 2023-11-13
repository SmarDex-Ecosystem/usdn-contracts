deploy:
	forge script script/Deploy.s.sol:DeployScript --fork-url $G --broadcast --verify -vvvv

snapshot:
	FOUNDRY_PROFILE=ci forge snapshot --no-match-contract TestSoladyMath

test:
	forge test -vvv
