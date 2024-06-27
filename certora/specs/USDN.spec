methods
{
    function MIN_DIVISOR() external returns (uint) envfree;
    function MAX_DIVISOR() external returns (uint) envfree;
    function MINTER_ROLE() external returns (bytes32) envfree;
    function maxTokens() external returns (uint) envfree;
    function sharesOf(address) external returns (uint) envfree;
    function balanceOf(address) external returns (uint) envfree;
    function totalSupply() external returns (uint) envfree;
    function divisor() external returns (uint) envfree;
    function rebaseHandler() external returns (address) envfree;
}

rule partialTransferShouldBeOKSpec(address recipient, uint divisor, uint tokens) {
    env e;

    require divisor > MIN_DIVISOR();
    require divisor < MAX_DIVISOR();
    require tokens >= 0;
    require tokens <= maxTokens();
    require rebaseHandler() == 0;

    grantRole(e, MINTER_ROLE(), e.msg.sender);

    mint(e, e.msg.sender, maxTokens());

    mathint shares_before = sharesOf(e, e.msg.sender);

    rebase(e, divisor);

    transfer(e, recipient, tokens);

    rebase(e, MIN_DIVISOR());

    mathint sender_shares_after = sharesOf(e.msg.sender);
    mathint recipient_shares_after = sharesOf(recipient);

    assert shares_before == sender_shares_after + recipient_shares_after, "shares sum invariant";
}


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