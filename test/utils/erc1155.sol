// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {ERC1155} from "../../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

contract NFT is ERC1155 {
    constructor() ERC1155("") {
        uint256[] memory ids;
        ids[0] = 1;
        ids[1] = 2;
        ids[2] = 3;
        ids[3] = 4;

        uint256[] memory amounts;
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        amounts[3] = 1;

        _mintBatch(msg.sender, amounts, amounts, bytes(""));
    }
}
