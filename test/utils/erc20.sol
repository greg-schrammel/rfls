// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "../../lib/solady/src/tokens/ERC20.sol";

contract _ERC20 is ERC20 {
    constructor(uint256 amount) {
        _mint(msg.sender, amount);
    }

    function name() public pure override returns (string memory) {
        return "";
    }

    function symbol() public pure override returns (string memory) {
        return "";
    }
}
