// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Raffle, RewardType, RaffleId, Reward, Participant, Ticket, Rfls} from "../src/rfls.sol";

import {_ERC20} from "./mocks/erc20.sol";
import {_ERC1155} from "./mocks/erc1155.sol";
import {_ERC721} from "./mocks/erc721.sol";

contract RflsTestSetupUtils is Test {
    Rfls rfls = new Rfls(address(this), address(this));

    _ERC20 token;
    _ERC1155 nft;
    _ERC721 nft2;

    address creator;
    address recipient;
    address[3] participants;

    function setUp() public virtual {
        creator = address(133);
        recipient = address(2131);

        participants[0] = address(1);
        participants[1] = address(2);
        participants[2] = address(3);

        vm.startPrank(creator);

        token = new _ERC20(100 ether);
        token.transfer(participants[0], 20 ether);
        token.transfer(participants[1], 30 ether);
        token.transfer(participants[2], 20 ether);

        nft = new _ERC1155();
        nft2 = new _ERC721();

        vm.stopPrank();
    }

    function _rewards() internal view returns (Reward[] memory) {
        Reward[] memory rewards = new Reward[](3);
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
        rewards[2] = Reward({
            addy: address(token),
            tokenId: 0,
            amount: 10,
            rewardType: RewardType.erc20
        });
        return rewards;
    }

    function _raffle() internal view returns (Raffle memory raffle) {
        raffle = Raffle({
            rewards: _rewards(),
            ticket: Ticket(address(token), 1 ether, 100, ""),
            deadline: block.number + 10,
            init: 0,
            creator: address(0),
            recipient: recipient,
            completed: false
        });
    }

    function _createRaffle(Raffle memory raffle) internal returns (RaffleId) {
        vm.startPrank(creator);

        nft.setApprovalForAll(address(rfls), true);
        nft2.approve(address(rfls), 1);
        token.approve(address(rfls), 1000);
        rfls.create(raffle);

        vm.stopPrank();

        return RaffleId.wrap(rfls.$rafflesCounter() - 1);
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
}
