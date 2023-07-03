// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Raffle, RewardType, RaffleId, Reward, Ticket, Rfls, InvalidDeadline, NotTheCreator, InProgress, Ended, NotStartedYet, AlreadyCompleted, NotEnoughTicketsRemaining} from "../src/rfls.sol";
import {RflsTestSetupUtils} from "./utils.sol";

contract RflsTest is Test, RflsTestSetupUtils {
    function testCreate() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        uint[3] memory balancesBefore;
        balancesBefore[0] = nft.balanceOf(address(creator), rewards[0].tokenId);
        balancesBefore[1] = nft2.balanceOf(address(creator));
        balancesBefore[2] = token.balanceOf(address(creator));

        _createRaffle(raffle, rewards);

        assertEq(nft.balanceOf(address(rfls), rewards[0].tokenId), 1);
        assertEq(
            nft.balanceOf(creator, rewards[0].tokenId),
            balancesBefore[0] - 1
        );

        assertEq(nft2.balanceOf(address(rfls)), 1);
        assertEq(nft2.balanceOf(creator), balancesBefore[1] - 1);

        assertEq(token.balanceOf(address(rfls)), rewards[2].amount);
        assertEq(
            token.balanceOf(creator),
            balancesBefore[2] - rewards[2].amount
        );
    }

    function testCreate_InvalidDeadline() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        raffle.deadline = block.number;

        vm.expectRevert(InvalidDeadline.selector);
        rfls.create(raffle, rewards);
    }

    function testHelpCreatorScrewedUp() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        uint256[3] memory balancesBefore;
        balancesBefore[0] = nft.balanceOf(address(creator), rewards[0].tokenId);
        balancesBefore[1] = nft2.balanceOf(address(creator));
        balancesBefore[2] = token.balanceOf(address(creator));

        RaffleId id = _createRaffle(raffle, rewards);

        vm.prank(creator);
        rfls.helpCreatorScrewedUp(id);

        assertEq(nft.balanceOf(address(rfls), rewards[0].tokenId), 0);
        assertEq(nft.balanceOf(creator, rewards[0].tokenId), balancesBefore[0]);

        assertEq(nft2.balanceOf(address(rfls)), 0);
        assertEq(nft2.balanceOf(creator), balancesBefore[1]);

        assertEq(token.balanceOf(address(rfls)), 0);
        assertEq(token.balanceOf(creator), balancesBefore[2]);
    }

    function testHelpCreatorScrewedUp_NotTheCretor() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        vm.expectRevert(NotTheCreator.selector);
        rfls.helpCreatorScrewedUp(id);
    }

    function testHelpCreatorScrewedUp_InProgress() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);
        _addParticipant(id, participants[0], 1);

        vm.startPrank(creator);

        vm.expectRevert(InProgress.selector);
        rfls.helpCreatorScrewedUp(id);

        vm.stopPrank();
    }

    function testParticipate() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        uint participantBalanceBefore = token.balanceOf(participants[0]);
        uint recipientBalanceBefore = token.balanceOf(recipient);

        uint ticketAmount = 1;

        _addParticipant(id, participants[0], ticketAmount);

        assertEq(rfls.balanceOf(participants[0], id), ticketAmount);
        assertEq(
            token.balanceOf(participants[0]),
            participantBalanceBefore - ticketAmount * raffle.ticket.price
        );

        uint fee = (raffle.ticket.price * rfls.FEE()) / 10_000;
        uint amountAfterFee = (ticketAmount * raffle.ticket.price) - fee;

        assertEq(token.balanceOf(rfls.FEE_RECEIVER()), fee);
        assertEq(
            token.balanceOf(recipient),
            recipientBalanceBefore + amountAfterFee
        );
    }

    function testParticipate_NotStartedYet() public {
        Raffle memory raffle = _raffle();
        raffle.init = block.number + 1;
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        vm.expectRevert(NotStartedYet.selector);
        rfls.participate(id, 1, participants[0]);
    }

    function testParticipate_Ended() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        vm.roll(raffle.deadline);

        vm.expectRevert(Ended.selector);
        rfls.participate(id, 1, participants[0]);
    }

    function testParticipate_NotEnoughTicketsRemaining() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();
        raffle.ticket.max = 1;

        RaffleId id = _createRaffle(raffle, rewards);

        vm.expectRevert(NotEnoughTicketsRemaining.selector);
        rfls.participate(id, 2, participants[0]);
    }

    function testFailParticipate_After_HelpCreatorScrewedUp() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        vm.prank(creator);
        rfls.helpCreatorScrewedUp(id);

        _addParticipant(id, participants[0], 1);
    }

    function testDraw() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        _addParticipant(id, participants[0], 4);
        _addParticipant(id, participants[1], 5);
        _addParticipant(id, participants[2], 2);

        uint tokenWinnerBalanceBefore = token.balanceOf(participants[1]);

        vm.roll(raffle.deadline + 1);
        rfls.draw(id);

        assertEq(nft.balanceOf(participants[0], 1), 1);
        assertEq(nft2.balanceOf(participants[2]), 1);
        assertEq(
            token.balanceOf(participants[1]),
            tokenWinnerBalanceBefore + rewards[2].amount
        );
    }

    function testDraw_NoParticipants() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        uint256[3] memory balancesBefore;
        balancesBefore[0] = nft.balanceOf(address(creator), rewards[0].tokenId);
        balancesBefore[1] = nft2.balanceOf(address(creator));
        balancesBefore[2] = token.balanceOf(address(creator));

        RaffleId id = _createRaffle(raffle, rewards);

        vm.roll(raffle.deadline + 1);
        rfls.draw(id);

        assertEq(nft.balanceOf(creator, rewards[0].tokenId), balancesBefore[0]);
        assertEq(nft2.balanceOf(creator), balancesBefore[1]);
        assertEq(token.balanceOf(creator), balancesBefore[2]);
    }

    function testDraw_InProgress() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        vm.roll(raffle.deadline);

        vm.expectRevert(InProgress.selector);
        rfls.draw(id);
    }

    function testDraw_Reenter() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        RaffleId id = _createRaffle(raffle, rewards);

        vm.roll(raffle.deadline + 1);

        rfls.draw(id);

        vm.expectRevert(AlreadyCompleted.selector);
        rfls.draw(id);
    }
}
