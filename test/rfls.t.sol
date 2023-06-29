// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {Raffle, Blocknumber, Reward, Participant, Ticket, rfls} from "../src/rfls.sol";
import {ERC20} from "../src/erc20.sol";

contract rflsTest is Test {
    rfls _rfls = new rfls(address(this), address(this));

    ERC20 usdc;
    address nft;

    address internal creator;
    address internal firstParticipant;

    function setUp() public virtual {
        creator = address(1);
        vm.label(creator, "Creator");
        firstParticipant = address(2);
        vm.label(firstParticipant, "First participant");

        vm.startPrank(creator);
        usdc = new ERC20(100, "usdc", 6, "usdc");
        usdc.transfer(firstParticipant, 50);
        vm.stopPrank();
    }

    function testCreate() public {
        Reward[] memory rewards = new Reward[](1);
        rewards[0] = Reward({addy: nft, tokenId: 1});

        Ticket memory ticket = Ticket({
            asset: usdc,
            price: 10 * (10 ^ 6), // 10 usdc
            max: 100
        });

        Raffle memory raffle = Raffle({
            rewards: rewards,
            ticket: ticket,
            deadline: Blocknumber.wrap(block.number + 1),
            creator: address(0),
            init: Blocknumber.wrap(0)
        });

        vm.prank(creator);
        _rfls.create(raffle);
    }
}
