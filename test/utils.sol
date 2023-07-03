// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {Raffle, RewardType, RaffleId, Reward, Ticket, Rfls} from "../src/rfls.sol";

import {_ERC20} from "./mocks/erc20.sol";
import {_ERC1155} from "./mocks/erc1155.sol";
import {_ERC721} from "./mocks/erc721.sol";

contract RflsTestSetupUtils is Test {
    Rfls rfls = new Rfls(address(this), address(this));

    _ERC20 erc20;
    _ERC1155 erc1155;
    _ERC721 erc721;

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

        erc20 = new _ERC20(100 ether);
        erc20.transfer(participants[0], 20 ether);
        erc20.transfer(participants[1], 30 ether);
        erc20.transfer(participants[2], 20 ether);

        erc1155 = new _ERC1155();
        erc721 = new _ERC721();

        vm.stopPrank();
    }

    function _rewards() internal view returns (Reward[] memory) {
        Reward[] memory rewards = new Reward[](3);
        rewards[0] = Reward({
            addy: address(erc1155),
            tokenId: 1,
            amount: 1,
            rewardType: RewardType.erc1155
        });
        rewards[1] = Reward({
            addy: address(erc721),
            tokenId: 1,
            amount: 1,
            rewardType: RewardType.erc721
        });
        rewards[2] = Reward({
            addy: address(erc20),
            tokenId: 0,
            amount: 10,
            rewardType: RewardType.erc20
        });
        return rewards;
    }

    function _raffle() internal view returns (Raffle memory raffle) {
        raffle = Raffle({
            ticket: Ticket(1 ether, 100, address(erc20), ""),
            deadline: block.number + 10,
            init: 0,
            creator: address(0),
            recipient: recipient,
            completed: false
        });
    }

    function _createRaffle(
        Raffle memory raffle,
        Reward[] memory rewards
    ) internal returns (RaffleId) {
        vm.startPrank(creator);

        erc1155.setApprovalForAll(address(rfls), true);
        erc721.approve(address(rfls), 1);
        erc20.approve(address(rfls), 1000);
        rfls.create(raffle, rewards);

        vm.stopPrank();

        return RaffleId.wrap(rfls.$rafflesCounter() - 1);
    }

    function _addParticipant(
        RaffleId id,
        address participant,
        uint tickets
    ) internal {
        vm.startPrank(participant);

        erc20.approve(address(rfls), type(uint).max);
        rfls.participate(id, tickets, address(participant));

        vm.stopPrank();
    }
}
