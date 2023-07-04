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
        balancesBefore[0] = erc1155.balanceOf(
            address(creator),
            rewards[0].tokenId
        );
        balancesBefore[1] = erc721.balanceOf(address(creator));
        balancesBefore[2] = erc20.balanceOf(address(creator));

        _createRaffle(raffle, rewards);

        assertEq(erc1155.balanceOf(address(rfls), rewards[0].tokenId), 1);
        assertEq(
            erc1155.balanceOf(creator, rewards[0].tokenId),
            balancesBefore[0] - 1
        );

        assertEq(erc721.balanceOf(address(rfls)), 1);
        assertEq(erc721.balanceOf(creator), balancesBefore[1] - 1);

        assertEq(erc20.balanceOf(address(rfls)), rewards[2].amount);
        assertEq(
            erc20.balanceOf(creator),
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
        balancesBefore[0] = erc1155.balanceOf(
            address(creator),
            rewards[0].tokenId
        );
        balancesBefore[1] = erc721.balanceOf(address(creator));
        balancesBefore[2] = erc20.balanceOf(address(creator));

        RaffleId id = _createRaffle(raffle, rewards);

        vm.prank(creator);
        rfls.helpCreatorScrewedUp(id);

        assertEq(erc1155.balanceOf(address(rfls), rewards[0].tokenId), 0);
        assertEq(
            erc1155.balanceOf(creator, rewards[0].tokenId),
            balancesBefore[0]
        );

        assertEq(erc721.balanceOf(address(rfls)), 0);
        assertEq(erc721.balanceOf(creator), balancesBefore[1]);

        assertEq(erc20.balanceOf(address(rfls)), 0);
        assertEq(erc20.balanceOf(creator), balancesBefore[2]);
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

        uint participantBalanceBefore = erc20.balanceOf(participants[0]);
        uint recipientBalanceBefore = erc20.balanceOf(recipient);

        uint ticketAmount = 10;

        _addParticipant(id, participants[0], ticketAmount);

        assertEq(rfls.balanceOf(participants[0], id), ticketAmount);
        assertEq(
            erc20.balanceOf(participants[0]),
            participantBalanceBefore - ticketAmount * raffle.ticket.price
        );

        uint fee = (raffle.ticket.price * rfls.FEE()) / 10_000;
        uint amountAfterFee = (ticketAmount * raffle.ticket.price) - fee;

        assertEq(erc20.balanceOf(rfls.FEE_RECEIVER()), fee);
        assertEq(
            erc20.balanceOf(recipient),
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

        uint tokenWinnerBalanceBefore = erc20.balanceOf(participants[1]);

        vm.roll(raffle.deadline + 1);
        rfls.draw(id);

        assertEq(erc1155.balanceOf(participants[0], 1), 1);
        assertEq(erc721.balanceOf(participants[2]), 1);
        assertEq(
            erc20.balanceOf(participants[1]),
            tokenWinnerBalanceBefore + rewards[2].amount
        );
    }

    function testDraw_NoParticipants() public {
        Raffle memory raffle = _raffle();
        Reward[] memory rewards = _rewards();

        uint256[3] memory balancesBefore;
        balancesBefore[0] = erc1155.balanceOf(
            address(creator),
            rewards[0].tokenId
        );
        balancesBefore[1] = erc721.balanceOf(address(creator));
        balancesBefore[2] = erc20.balanceOf(address(creator));

        RaffleId id = _createRaffle(raffle, rewards);

        vm.roll(raffle.deadline + 1);
        rfls.draw(id);

        assertEq(
            erc1155.balanceOf(creator, rewards[0].tokenId),
            balancesBefore[0]
        );
        assertEq(erc721.balanceOf(creator), balancesBefore[1]);
        assertEq(erc20.balanceOf(creator), balancesBefore[2]);
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
