// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Raffle, RaffleId, Reward, Participant, Ticket, Rfls} from "../src/rfls.sol";

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
        token = new Token(100 ether);
        token.transfer(firstParticipant, 50 ether);
        nft = new NFT();
        vm.stopPrank();
    }

    function makeRewards() internal view returns (Reward[] memory) {
        Reward[] memory rewards = new Reward[](1);
        rewards[0] = Reward({addy: address(nft), tokenId: 1});
        return rewards;
    }

    function makeRaffle() internal view returns (Raffle memory raffle) {
        raffle = Raffle({
            rewards: makeRewards(),
            ticket: Ticket(address(token), 1 ether, 100),
            deadline: block.number + 10,
            creator: address(0),
            init: 0
        });
    }

    function createRaffle(Raffle memory raffle) internal returns (RaffleId) {
        vm.startPrank(creator);

        nft.setApprovalForAll(address(rfls), true);
        rfls.create(raffle);

        vm.stopPrank();

        return RaffleId.wrap(rfls.$rafflesCounter() - 1);
    }

    function testCreate() public {
        Raffle memory raffle = makeRaffle();

        uint256 creatorRewardBalanceBefore = nft.balanceOf(
            address(creator),
            raffle.rewards[0].tokenId
        );

        createRaffle(raffle);

        assert(nft.balanceOf(address(rfls), raffle.rewards[0].tokenId) == 1);
        assert(
            nft.balanceOf(address(creator), raffle.rewards[0].tokenId) ==
                creatorRewardBalanceBefore - 1
        );
    }

    function testParticipate() public {
        Raffle memory raffle = makeRaffle();

        RaffleId raffleId = createRaffle(raffle);

        uint participantBalanceBefore = token.balanceOf(firstParticipant);

        vm.prank(firstParticipant);
        rfls.participate(raffleId, 1, address(firstParticipant));

        assert(rfls.balanceOf(address(firstParticipant), raffleId) == 1);
        assert(
            token.balanceOf(firstParticipant) ==
                participantBalanceBefore - raffle.ticket.price
        );

        uint ticketPrice = raffle.ticket.price;
        uint fee = ticketPrice > 100 ? (ticketPrice * rfls.FEE()) / 10_000 : 0;
        uint amountAfterFee = (1 * raffle.ticket.price) - fee;

        emit log_uint(fee);
        emit log_uint(amountAfterFee);
        // raffle.ticket.price
        // assert(
        //     token.balanceOf(rfls.FEE_RECEIVER()) ==
        // );
    }
}
