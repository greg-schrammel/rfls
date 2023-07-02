// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Raffle, RewardType, RaffleId, Reward, Participant, Ticket, Rfls} from "../src/rfls.sol";
import {RflsTestSetupUtils} from "./utils.sol";

contract RflsTest is Test, RflsTestSetupUtils {
    function testCreate() public {
        Raffle memory raffle = _raffle();

        uint256 creatorRewardBalanceBefore = nft.balanceOf(
            address(creator),
            raffle.rewards[0].tokenId
        );

        _createRaffle(raffle);

        assertEq(nft.balanceOf(address(rfls), raffle.rewards[0].tokenId), 1);
        assertEq(
            nft.balanceOf(address(creator), raffle.rewards[0].tokenId),
            creatorRewardBalanceBefore - 1
        );

        assertEq(nft2.balanceOf(address(rfls)), 1);
        assertEq(nft2.balanceOf(address(creator)), 0);
    }

    function testParticipate() public {
        Raffle memory raffle = _raffle();

        RaffleId raffleId = _createRaffle(raffle);

        uint participantBalanceBefore = token.balanceOf(participants[0]);
        uint recipientBalanceBefore = token.balanceOf(address(recipient));

        addParticipant(raffleId, raffle, participants[0], 1);

        assertEq(rfls.balanceOf(address(participants[0]), raffleId), 1);
        assertEq(
            token.balanceOf(participants[0]),
            participantBalanceBefore - raffle.ticket.price
        );

        uint fee = (raffle.ticket.price * rfls.FEE()) / 10_000;
        uint amountAfterFee = (1 * raffle.ticket.price) - fee;

        assertEq(token.balanceOf(rfls.FEE_RECEIVER()), fee);
        assertEq(
            token.balanceOf(address(recipient)),
            recipientBalanceBefore + amountAfterFee
        );
    }

    function testDraw() public {
        Raffle memory raffle = _raffle();
        RaffleId raffleId = _createRaffle(raffle);

        addParticipant(raffleId, raffle, participants[0], 4);
        addParticipant(raffleId, raffle, participants[1], 5);
        addParticipant(raffleId, raffle, participants[2], 2);

        vm.roll(raffle.deadline + 1);
        rfls.draw(raffleId);

        assertEq(nft.balanceOf(participants[0], 1), 1);
        assertEq(nft2.balanceOf(participants[2]), 1);
    }
}
