// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Raffle, Blocknumber, Reward, Participant, Ticket, Rfls} from "../src/rfls.sol";

import {Token} from "./utils/erc20.sol";
import {NFT} from "./utils/erc1155.sol";

contract RflsTest is Test {
    Rfls rfls = new Rfls(address(this), address(this));

    Token token;
    NFT nft;

    address internal creator;
    address internal firstParticipant;

    function setUp() public virtual {
        creator = address(1);
        vm.label(creator, "Creator");
        firstParticipant = address(2);
        vm.label(firstParticipant, "First participant");

        vm.startPrank(creator);
        token = new Token(100);
        token.transfer(firstParticipant, 50);
        nft = new NFT();
        vm.stopPrank();
    }

    function testCreate() public {
        Reward[] memory rewards = new Reward[](1);
        rewards[0] = Reward({addy: address(nft), tokenId: 1});

        Ticket memory ticket = Ticket({
            asset: address(token),
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

        uint256 creatorRewardBalanceBefore = nft.balanceOf(
            address(creator),
            rewards[0].tokenId
        );

        vm.startPrank(creator);
        nft.setApprovalForAll(address(rfls), true);
        rfls.create(raffle);
        vm.stopPrank();

        assert(nft.balanceOf(address(rfls), rewards[0].tokenId) == 1);
        assert(
            nft.balanceOf(address(creator), rewards[0].tokenId) ==
                creatorRewardBalanceBefore - 1
        );
    }
}
