deploy:
	forge script script/Deploy.s.sol:DeployScript --fork-url $G --broadcast --verify -vvvv

snapshot:
	FOUNDRY_PROFILE=ci forge snapshot

test:
	forge test -vvv
