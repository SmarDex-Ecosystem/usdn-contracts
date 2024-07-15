methods
{
    function MIN_DIVISOR() external returns (uint) envfree;
    function MAX_DIVISOR() external returns (uint) envfree;
    function MINTER_ROLE() external returns (bytes32) envfree;
    function maxTokens() external returns (uint) envfree;
    function sharesOf(address) external returns (uint) envfree;
    function balanceOf(address) external returns (uint) envfree;
    function totalSupply() external returns (uint) envfree;
    function totalShares() external returns (uint) envfree;
    function divisor() external returns (uint) envfree;
    function rebaseHandler() external returns (address) envfree;
}

ghost mathint sumOfShares {
    init_state axiom sumOfShares == 0;
}

ghost mathint numberOfChangesOfShares {
	init_state axiom numberOfChangesOfShares == 0;
}

hook Sload uint256 shares _shares[KEY address addr] {
    require sumOfShares >= to_mathint(shares);
}

hook Sstore _shares[KEY address addr] uint256 newValue (uint256 oldValue) {
    sumOfShares = sumOfShares - oldValue + newValue;
    numberOfChangesOfShares = numberOfChangesOfShares + 1;
}

invariant totalSharesIsSumOfSharesBalances()
    to_mathint(totalShares()) == sumOfShares;

rule partialTransferShouldFailSpec(address recipient, uint divisor, uint tokens) {
    env e;

    require divisor > MIN_DIVISOR();
    require divisor < MAX_DIVISOR();
    require tokens >= 0;
    require tokens <= maxTokens();
    require rebaseHandler() == 0;

    grantRole(e, MINTER_ROLE(), e.msg.sender);

    mint(e, e.msg.sender, maxTokens());

    rebase(e, divisor);

    transfer(e, recipient, tokens);

    rebase(e, MIN_DIVISOR());

    mathint sender_balance_after = balanceOf(e.msg.sender);
    mathint recipient_balance_after = balanceOf(recipient);
    mathint total_supply = totalSupply();

    assert total_supply == sender_balance_after + recipient_balance_after, "balances sum invariant";
}

rule partialTransferKnownBadValuesSpec(address recipient) {
    env e;

    require balanceOf(e.msg.sender) == 0;
    require balanceOf(recipient) == 0;
    require totalSupply() == 0;
    require divisor() == MAX_DIVISOR();
    require rebaseHandler() == 0;

    grantRole(e, MINTER_ROLE(), e.msg.sender);

    mint(e, e.msg.sender, maxTokens());

    rebase(e, 1472780595);

    transfer(e, recipient, 100000000);

    rebase(e, MIN_DIVISOR());

    mathint sender_balance_after = balanceOf(e.msg.sender);
    mathint recipient_balance_after = balanceOf(recipient);
    mathint total_supply = totalSupply();

    assert total_supply == sender_balance_after + recipient_balance_after, "balances sum invariant";
}