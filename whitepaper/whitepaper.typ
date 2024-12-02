#import "@preview/graceful-genetics:0.2.0": template

// Configure equation numbering and spacing.
#set math.equation(numbering: "(1)")

// Configure appearance of equation references
#show ref: it => {
  if it.element != none and it.element.func() == math.equation {
    // Override equation references.
    link(
      it.element.location(),
      numbering(
        it.element.numbering,
        ..counter(math.equation).at(it.element.location()),
      ),
    )
  } else {
    // Other references as usual.
    it
  }
}

#show: template.with(
  title: [Ultimate Synthetic Delta Neutral],
  authors: (
    (
      name: "TBD",
      institution: "RA2 Tech SA",
      location: "Switzerland",
      mail: "info@ra2.tech",
    ),
  ),
  abstract: [
    #lorem(50)
  ],
  keywords: ("DeFi", "Blockchain", "Synthetic Assets", "Delta Neutral"),
  make-venue: [],
)

#show heading.where(level: 3): set text(style: "italic", weight: "medium")

= Introduction

= Protocol architecture

= USDN Token

== Overview

The USDN token is a synthetic USD token designed to approximate the value of one US dollar while delivering consistent
returns to its holders. Unlike a stablecoin, USDN does not claim to maintain a rigid peg to \$1. Instead, it oscillates
slightly above or below this reference value, supported by market forces and the protocol's innovative mechanisms.

== Price

Due to the algorithmic nature of the USDN token, its price $P_"usdn"$ can be calculated using the following formula:

$ P_"usdn" = frac(B_"vault" P_"asset", S_"tot") $ <eq:usdn_price>

where $B_"vault"$ is the total assets held in the protocol's vault, $P_"asset"$ is the price of the asset token in USD,
and $S_"tot"$ is the total supply of USDN tokens.

== Token Minting

USDN tokens are minted whenever a deposit is made into the protocol's vault. The amount of minted USDN $A_"usdn"$ is
calculated by dividing the dollar value of the deposited assets by the USDN price:

$ A_"usdn" = frac(A_"asset" P_"asset", P_"usdn") $ <eq:usdn_minting>

Taking into account @eq:usdn_price, the minting formula can be rewritten as:

$ A_"usdn" = frac(A_"asset" S_"tot", B_"vault") $

== Token Burning

When assets are removed from the protocol's vault, USDN tokens are burned in proportion to the withdrawn amount,
following @eq:usdn_minting. Thus, for a given amount of USDN to be burned, the corresponding withdrawn assets amount is:

$ A_"asset" = frac(A_"usdn" P_"usdn", P_"asset") = frac(A_"usdn" B_"vault", S_"tot") $

== Yield Sources

From @eq:usdn_price, it is clear that the USDN price is influenced by the total assets held in the protocol's vault.
As such, if the vault balance increases as a result of position fees, losses from long positions, or funding payments,
the USDN price will rise. When a certain threshold is reached, the token rebases to a price slightly above \$1 by
increasing the total supply and balance of each holder. This increase in balance represents the yield of the USDN token. The rebase mechanism ensures that yields do not indice a price that significantly exceeds the value of \$1.

=== Wrapped USDN

Not all DeFi protocols support tokens which balance increases over time without transfers. To help wit
integration, a wrapped version of the token, WUSDN, was created. This token behaves like a normal ERC20 token and sees
its price increase over time, instead of the balances.

= Vault

= Long

== Tick

== PNL

= Funding

= Imbalance