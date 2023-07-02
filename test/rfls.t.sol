// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Raffle, RewardType, RaffleId, Reward, Participant, Ticket, Rfls} from "../src/rfls.sol";

import {_ERC20} from "./utils/erc20.sol";
import {_ERC1155} from "./utils/erc1155.sol";
import {_ERC721} from "./utils/erc721.sol";

contract RflsTest is Test {
    Rfls rfls = new Rfls(address(this), address(this));

    _ERC20 token;
    _ERC1155 nft;
    _ERC721 nft2;

    address internal creator;
    address internal recipient;
    address internal firstParticipant;
    address internal secondParticipant;
    address internal thirdParticipant;

    function setUp() public virtual {
        creator = address(133);
        recipient = address(2131);

        firstParticipant = address(1);
        secondParticipant = address(2);
        thirdParticipant = address(3);

        vm.startPrank(creator);

        token = new _ERC20(100 ether);
        token.transfer(firstParticipant, 20 ether);
        token.transfer(secondParticipant, 30 ether);
        token.transfer(thirdParticipant, 20 ether);

        nft = new _ERC1155();
        nft2 = new _ERC721();

        vm.stopPrank();
    }

    function makeRewards() internal view returns (Reward[] memory) {
        Reward[] memory rewards = new Reward[](2);
        rewards[0] = Reward({
            addy: address(nft),
            tokenId: 1,
            amount: 1,
            rewardType: RewardType.erc1155
        });
        rewards[1] = Reward({
            addy: address(nft2),
            tokenId: 1,
            amount: 1,
            rewardType: RewardType.erc721
        });
        return rewards;
    }

    function makeRaffle() internal view returns (Raffle memory raffle) {
        raffle = Raffle({
            rewards: makeRewards(),
            ticket: Ticket(address(token), 1 ether, 100),
            deadline: block.number + 10,
            init: 0,
            creator: address(0),
            recipient: recipient,
            completed: false
        });
    }

    function createRaffle(Raffle memory raffle) internal returns (RaffleId) {
        vm.startPrank(creator);

        nft.setApprovalForAll(address(rfls), true);
        nft2.approve(address(rfls), 1);
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

        assert(nft2.balanceOf(address(rfls)) == 1);
        assert(nft2.balanceOf(address(creator)) == 0);
    }

    function addParticipant(
        RaffleId id,
        Raffle memory raffle,
        address participant,
        uint tickets
    ) internal {
        vm.startPrank(participant);

        token.approve(address(rfls), raffle.ticket.price * tickets);
        rfls.participate(id, tickets, address(participant));

        vm.stopPrank();
    }

    function testParticipate() public {
        Raffle memory raffle = makeRaffle();

        RaffleId raffleId = createRaffle(raffle);

        uint participantBalanceBefore = token.balanceOf(firstParticipant);
        uint recipientBalanceBefore = token.balanceOf(address(recipient));

        addParticipant(raffleId, raffle, firstParticipant, 1);

        assert(rfls.balanceOf(address(firstParticipant), raffleId) == 1);
        assert(
            token.balanceOf(firstParticipant) ==
                participantBalanceBefore - raffle.ticket.price
        );

        uint fee = (raffle.ticket.price * rfls.FEE()) / 10_000;
        uint amountAfterFee = (1 * raffle.ticket.price) - fee;

        assert(token.balanceOf(rfls.FEE_RECEIVER()) == fee);
        assert(
            token.balanceOf(address(recipient)) ==
                recipientBalanceBefore + amountAfterFee
        );
    }

    function testDraw() public {
        Raffle memory raffle = makeRaffle();
        RaffleId raffleId = createRaffle(raffle);

        addParticipant(raffleId, raffle, firstParticipant, 4);
        addParticipant(raffleId, raffle, secondParticipant, 5);
        addParticipant(raffleId, raffle, thirdParticipant, 2);

        vm.roll(raffle.deadline + 1);
        rfls.draw(raffleId);

        assert(nft.balanceOf(firstParticipant, 1) == 1);
        assert(nft2.balanceOf(thirdParticipant) == 1);
    }
}
