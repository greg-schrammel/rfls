// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC1155} from "../../lib/solady/src/tokens/ERC1155.sol";

contract _ERC1155 is ERC1155 {
    uint256[] ids;
    uint256[] amounts;

    constructor() {
        ids.push(1);
        ids.push(2);
        ids.push(3);
        ids.push(4);

        amounts.push(1);
        amounts.push(1);
        amounts.push(1);
        amounts.push(1);

        _batchMint(msg.sender, ids, amounts, bytes(""));
    }

    string[] s;

    function uri(uint256 id) public view override returns (string memory) {
        return s[id];
    }
}
