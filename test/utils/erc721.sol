// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "../../lib/solady/src/tokens/ERC721.sol";

contract _ERC721 is ERC721 {
    constructor() {
        _mint(msg.sender, 1);
    }

    string[] s;

    function tokenURI(uint256 id) public view override returns (string memory) {
        return s[id];
    }

    function name() public pure override returns (string memory) {
        return "";
    }

    function symbol() public pure override returns (string memory) {
        return "";
    }
}
