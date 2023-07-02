// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC721} from "../../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

contract _ERC721 is ERC721 {
    constructor() ERC721("", "") {
        _mint(msg.sender, 1);
    }
}
