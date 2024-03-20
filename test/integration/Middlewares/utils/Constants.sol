// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

/* -------------------------------------------------------------------------- */
/*                             Mocked oracle data                             */
/* -------------------------------------------------------------------------- */

uint256 constant ETH_PRICE = 2000 gwei;
uint256 constant ETH_CONF = 20 gwei;

// WSTETH DATA
bytes constant PYTH_DATA =
    hex"504e41550100000003b801000000030d027400204ef04a5b8429a539232c8527f59b3a4637fc397594c313105f4dc01ce80202f8a7f8956b1d85785e5985968f25563a020fe8c5f38ded7b9701f9d42291000371d8c15b110483a830093ac446caa1624c2586b85cc755300b64c5b7cdc3f70b4fb091789274c8496f81d2bef1a46d66cfaace8c692db516e68354425950aff6000459c82a0dce0febedc49802e0c313f972c5c1e0162c93633fd211888eedc868503771789a764b60388385c51091e840cf15f38f55ec6d74038f0f2a40df353fa10107a70b1476d8a056c748450b6320314e285c311a074fcf474a9e170c472a253c4f300410b5709021fb44b13f5cc811f7ca4ca0d0e9d5d3fb330bbb0ad0422badbe01085a966128e731ffb0e03248233c56256f3a5bbce7954617bcce141441a9733fa76318cc51dc3c2a402602361777adba56724afa00b63d923abde6ba11f1c484b2000ab68e31badc2c395d92b8cfe9cc72ea27b2018165b1327a029e7d62e028bfbf056e02102d5825e1bced254689c5e47faed294a97f833cfef6fc65d610b2719d28010ba6782e4a07ce48d1a3e845d6c70b5928dce115d81f47d6b077079fac4b45fa1743223293fc8662bd7d4a6d569aa1fccf7492f8a50835e76ecbd724420a8c3117000c5b8dd9b920aac4bcf325b678bde0489d7deceafe87d0fb29a040e953543451527ceaa880fb4c4874aa57305c2f01c011d5fa45018c3de9a0201b399e3df73be0010daafd91560dd9adb83b93d9dfa391773123b1c2ec6d94def25eaca5e389192ba9040188a95c03451dbe13215b40a5004e2df7e17edd9da3f552b10c93f3132346000eb2757cfc89791bb380daac0e16e543ee87a468f5a028820adff0c32a568d67d277edbe4ced802e27f67dc6cf6cee6803510d3b7c922db1ab85c4cf3b6da31433000fc75bf49b4ce2b63118d89c1334049cc2bc3c5a1d35eeb9ebae9fc64653850eea3aeedb6c8bdf0b98e760ee565a6ebea94cd4ac8e14c7e1459dbd18696c0cb23e011041abd582096bbe63d086856bcde7ebce2abba8528aaa2b1cb51928619bbc64424a5a43a7bfbc987d893a768ec63b2d8dafa8aaeba161bbf9b87dad78aca6485a00123341b75bf87c09b41cfd26d5a91b08c1b771f96a9fadd677fa31fb9d211ff3dc703fee163e1892f16d4d3968494150e2bc366a7611b574af8f6809b0a5639aa50065ae4a6800000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa71000000000239c07601415557560000000000074158b000002710323cba9c6dde05e45fbcea06218184098bb180aa010055006df640f3b8963d8f8358f791f352b8364513f6ab1cca5ed3f1f7b5448980e7840000003fe24748f7000000004147019afffffff80000000065ae4a680000000065ae4a660000004073c77b400000000045368f220a3d69a1e7cbcdc7d1d4d8139c1ae902ce0f62215a6d3a3af12f012a95d75b38cbad74f20d41fc252c14164268e8ec0b733bdde3e90526fc63f78c4d5b208f0b18ddb3152ae2cc039815e615939fe9699c8fde25535adc9a5c24422511f633feb371efd7b72db7f684f227076e86a8778670d4eee9e0ffacab69344f002f4ceedbdcd3bd7551cd270e5453789c90c67cf9a27b1e841c9e35a1aa88184df3d41a84610dc1b607f1177218c9f6248de0df5fc95cbb8531b6d30058ac9db5281cd2aaaff4d294e2a3b7f9";
uint256 constant PYTH_DATA_PRICE = 274_379_262_199;
uint256 constant PYTH_DATA_CONF = 1_095_172_506;
uint256 constant PYTH_DATA_DECIMALS = 8;

// STETH DATA
bytes constant PYTH_DATA_STETH =
    hex"504e41550100000003b801000000030d027400204ef04a5b8429a539232c8527f59b3a4637fc397594c313105f4dc01ce80202f8a7f8956b1d85785e5985968f25563a020fe8c5f38ded7b9701f9d42291000371d8c15b110483a830093ac446caa1624c2586b85cc755300b64c5b7cdc3f70b4fb091789274c8496f81d2bef1a46d66cfaace8c692db516e68354425950aff6000459c82a0dce0febedc49802e0c313f972c5c1e0162c93633fd211888eedc868503771789a764b60388385c51091e840cf15f38f55ec6d74038f0f2a40df353fa10107a70b1476d8a056c748450b6320314e285c311a074fcf474a9e170c472a253c4f300410b5709021fb44b13f5cc811f7ca4ca0d0e9d5d3fb330bbb0ad0422badbe01085a966128e731ffb0e03248233c56256f3a5bbce7954617bcce141441a9733fa76318cc51dc3c2a402602361777adba56724afa00b63d923abde6ba11f1c484b2000ab68e31badc2c395d92b8cfe9cc72ea27b2018165b1327a029e7d62e028bfbf056e02102d5825e1bced254689c5e47faed294a97f833cfef6fc65d610b2719d28010ba6782e4a07ce48d1a3e845d6c70b5928dce115d81f47d6b077079fac4b45fa1743223293fc8662bd7d4a6d569aa1fccf7492f8a50835e76ecbd724420a8c3117000c5b8dd9b920aac4bcf325b678bde0489d7deceafe87d0fb29a040e953543451527ceaa880fb4c4874aa57305c2f01c011d5fa45018c3de9a0201b399e3df73be0010daafd91560dd9adb83b93d9dfa391773123b1c2ec6d94def25eaca5e389192ba9040188a95c03451dbe13215b40a5004e2df7e17edd9da3f552b10c93f3132346000eb2757cfc89791bb380daac0e16e543ee87a468f5a028820adff0c32a568d67d277edbe4ced802e27f67dc6cf6cee6803510d3b7c922db1ab85c4cf3b6da31433000fc75bf49b4ce2b63118d89c1334049cc2bc3c5a1d35eeb9ebae9fc64653850eea3aeedb6c8bdf0b98e760ee565a6ebea94cd4ac8e14c7e1459dbd18696c0cb23e011041abd582096bbe63d086856bcde7ebce2abba8528aaa2b1cb51928619bbc64424a5a43a7bfbc987d893a768ec63b2d8dafa8aaeba161bbf9b87dad78aca6485a00123341b75bf87c09b41cfd26d5a91b08c1b771f96a9fadd677fa31fb9d211ff3dc703fee163e1892f16d4d3968494150e2bc366a7611b574af8f6809b0a5639aa50065ae4a6800000000001ae101faedac5851e32b9b23b5f9411a8c2bac4aae3ed4dd7b811dd1a72ea4aa71000000000239c07601415557560000000000074158b000002710323cba9c6dde05e45fbcea06218184098bb180aa01005500846ae1bdb6300b817cee5fdee2a6da192775030db5615b94a465f53bd40850b5000000375f23e214000000000e6e0299fffffff80000000065ae4a680000000065ae4a6600000037ad1be60000000000104328480aabd4efd4592e752287ffefb641fd39ac3f87723e7de3a729c3db8e7b22ffbb90e701e42e280a8a0166590e9f32332319c04d7136ea63d1390d248877d89bfec50924ffa25e07251b23ba4912b5b11afa88c50af8369daa15a2bec5e9ba40e1bcf96fe7eea0cadbfdab2598d0a1c44411c9b3d442d463538022821500d68dd21e640a1975c3bae49f0489c5d990c67cf9a27b1e841c9e35a1aa88184df3d41a84610dc1b607f1177218c9f6248de0df5fc95cbb8531b6d30058ac9db5281cd2aaaff4d294e2a3b7f9";
uint256 constant PYTH_DATA_STETH_PRICE = 237_819_388_436;
uint256 constant PYTH_DATA_STETH_CONF = 242_090_649;
uint256 constant PYTH_DATA_STETH_DECIMALS = 8;

uint256 constant PYTH_DATA_TIMESTAMP = 1_705_921_128;
