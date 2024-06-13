// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

/* -------------------------------------------------------------------------- */
/*                             Mocked oracle data                             */
/* -------------------------------------------------------------------------- */

uint256 constant ETH_PRICE = 2000 gwei;
uint256 constant ETH_CONF = 20 gwei;

// ETH DATA
bytes constant PYTH_DATA_ETH =
    hex"504e41550100000003b801000000040d00a7e5adc068fb94877dd1e0b08520fdb95044fd3c9f601eca3f3c33af510f8f686490a5ef15c7eb4986b2c97743cd3ccfedf6127eb21b61a85f66925dd5548e30000101b43be6f649fbe8daa555bcb815b36f2bd145da8123ffba94a8e520fefdf0a922f18f936d77d4a6de01af44eb0777ccb2026a5c12c743a0e1823b7567ec21170002d90cd59d5caf0824d2bcbb288868bf5c102c3e6130c660daa31985f2a5e6b72e4bf836b6e5aaa684d9135e526afe2f12a7c320171c5bfb5c0c0c385704964c340103041dd449b450f84ff6da07cd019835a9691c1fc0fb311677e1f7cb1b4bc1ad241760ca91c740731ebefdfebbdba584fe93f33b141d10b9425720192d938b8b570106eb526b954ed58689527c42362b6cbe3706679d63faf9cbccdb009fc45002b27f6554a10edd5e787fce87d6260360212e361aa7acf992348c57157327c48605250007d3b12f362e7cd427aa6494c4fa9e38b175c6584879a378f809935e383fe7139f53a25f5e678d49f40a947328b555043167228e367baabffa8660e1f05ef0a2cf0009d29b43f180775a7392317fe90c1d927a5781d97a64670275ef592c351ee4ea233f0bc89e3e8bd1eb55d721bbb39e291ce5360c6df26a8bfa679ce5e0239cc0a4000a6ddf81272717c891fd3e822e1481d8b5ea98acf9ef3227f4435a4f67908fbe836be434ee33a3b49476d9e1016458d20143de522450e85743c0b288c750cb4385010b11af10a7fd6f16bc3c663cbb4e7ace1c6e2b98a2586a9eb0507e0b224adb2b9963f0e08577ca9a1da203bd4c5defffaf4a3b9e5522de264042f5c1fb8efbfbea000c83c74ac5d478ca48d00ebd01836edd5de7cebfd23b051a1987d512f70d5706d2515a01dc5c0f674b791c84d31926de4562765c811ad97489a64a52c286020f43000d8656b2fafa3b2ac07ca4d5535ebd7e2b1a30593eb79dcd5865f0b19c1928ed181f35f9949eaaed76ed37f018a195140f1d430f2f45ef756f80164258f31e39b9000eccafc78553ca3a2e88b5e0a1fb7d96a62c67cd74f53a09394263ba8d0c19d6225f17129850c65ceec16d62e68ddaa2141c3cb2fa5c55acf8ea979fbbabe1a47d0112728c946f7959e22f57c8eb21e0a6d58a0b6de534e11c300ecbc187ed817966701bb53ce2be436bce3fc6eaa3c9c5ef7cbefe9b4e83b556acbbc2dc7ee133abe401662367f000000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa710000000003143c6501415557560000000000081e312900002710db6c50935a25de7be12b52e8fc0db4cd1a7edc5a01005500ff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace0000004761e37698000000000e32c22afffffff800000000662367f000000000662367ef0000004755752aa0000000000d1ae2f30a3a03d0677b2831e3d64bd4fc1d11227a816294a76c8451aa21f5842b28c2214946ad5113d604634a09e47ac1f53f9cf1a337c169cb7291bf18e1518fe7a77e7465d101bc55a79e2c501c4ff7690429d59ac4db3e5ebe91eadac7dec344875b491c9ad41740a629a338056928be521b397e34704ad1e24927747c1f686251c4f54438b749dbcf909ef07c8b38ff1c4b7fe041f62cc187268bc877575183bacce410b1b42b5ab4a8cca07927f946d6ceb2133f786a1e5d53350d5358a497a656a2ef6b18afc68b57b6";
uint256 constant PYTH_DATA_ETH_PRICE = 306_584_975_000;
uint256 constant PYTH_DATA_ETH_CONF = 238_207_530;
uint256 constant PYTH_DATA_ETH_DECIMALS = 8;

uint256 constant PYTH_DATA_TIMESTAMP = 1_713_596_400; // 2024-04-20 07:00:00 UTC
