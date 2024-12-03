#import "@preview/charged-ieee:0.1.3": ieee

#show: ieee.with(
  title: [Ultimate Synthetic Delta Neutral],
  abstract: [
    This paper present a new decentralized protocol proposing two defi products : making yield by being exposed in dollar and long leverage trading.
    It covers the mathematical principles and choices for both products.
    A new token is introduced, USDN, a tradable ERC20 and making value over time.
    It explain how we store value in a vault for the synthetic dollar side and then how we store long and calculate their profit and loss (PnL).
    This whitepaper describes the mechanics of funding and imbalance limits to ensure the right behavior of the protocol.
  ],
  index-terms: ("Defi", "Blockchain"),
)

= Introduction

The decentralized finance (DeFi) ecosystem has long sought alternatives to fiat-backed tokens, aiming to provide users
with assets that combine dollar-like stability with yield generation. However, existing solutions, particularly stablecoins, suffer
from inherent flaws: they are often centralized, opaque, and yield-free for holders.

USDN aim to solve this by operating a fully decentralized structured product.
Its architecture eliminates dependencies on centralized exchanges (CEXs) or custodial intermediaries.
Instead, users need to provide a predefined asset in order to mint USDN or open long leveraged positions.
This asset can indirectly bring incentives to users and be able to use financial products.
In the first instance, the predefined asset is the wrapped staked ETH (wstETH) from Lido.

= Protocol architecture

= USDN Token

= Vault

= Long

== Tick

== PNL

= Funding

= Imbalance