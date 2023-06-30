// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "forge-std/Test.sol";

import {ERC20} from "../lib/openzeppelin-contracts/contracts//token/ERC20/ERC20.sol";
import {ERC721} from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

interface NativeWrapper {
    function deposit() external payable;

    function withdraw(uint) external;
}

error NotStartedYet();
error Ended();
error InProgress();
error InvalidDeadline();
error NotEnoughTicketsRemaining();

type RaffleId is uint256;

struct Reward {
    address addy;
    uint256 tokenId;
}

struct Ticket {
    address asset; // usdc, weth
    uint256 price;
    uint256 max;
}

struct Raffle {
    address creator;
    Ticket ticket;
    Reward[] rewards;
    uint256 deadline;
    uint256 init;
}

struct Participant {
    address addy;
    uint256 tickets;
}

library WeightedRandom {
    function pickOne(
        uint256 random,
        Participant[] memory participants
    ) internal pure returns (uint256) {
        unchecked {
            for (uint256 i = 0; i < participants.length; i++) {
                if (random < participants[i].tickets) return i;
                random -= participants[i].tickets;
            }
            return 0; // should never get here
        }
    }

    function pickMultiple(
        Participant[] memory participants,
        uint256 max,
        uint256 weightsSum,
        uint256 blocknumber
    ) internal view returns (address[] memory) {
        uint256 random = uint256(
            // can wait until the result is favorable? yes (only if not called after 255 blocks)
            // but anyone can call while you waiting hopefully a bot will call right at the deadline
            blockhash(block.number - blocknumber > 254 ? 254 : blocknumber)
            // random must be less than weightsSum
        ) % weightsSum;

        address[] memory winners = new address[](max);
        unchecked {
            for (uint256 i = 0; i < max; i++) {
                uint256 winnerIndex = pickOne(random, participants);
                winners[i] = participants[winnerIndex].addy;

                // remove winner from participants
                participants[winnerIndex] = participants[
                    participants.length - 1
                ];
                delete participants[participants.length - 1];

                if (participants.length == 0) return winners;
            }
        }
        return winners;
    }
}

contract Rfls is Test {
    event Created(Raffle indexed raffle);
    event Completed(RaffleId indexed raffle, address[] indexed winners);
    event BoughtTicket(
        RaffleId indexed raffle,
        uint256 indexed amount,
        address indexed to
    );

    mapping(RaffleId => Raffle) $raffles;
    mapping(RaffleId => Participant[]) $participants;
    mapping(RaffleId => mapping(address => uint256)) $participantIndex;
    mapping(RaffleId => uint256) $ticketsCounter;
    uint256 public $rafflesCounter = 0;

    uint8 public constant FEE = 100;
    address public immutable FEE_RECEIVER;

    address immutable WRAPPED_NATIVE;

    constructor(address wrappedNative, address fee_receiver) {
        WRAPPED_NATIVE = wrappedNative;
        FEE_RECEIVER = fee_receiver;
    }

    function getRaffle(RaffleId id) public view returns (Raffle memory) {
        return $raffles[id];
    }

    function create(Raffle memory raffle) public {
        if (block.number > raffle.deadline) revert InvalidDeadline();

        RaffleId id = RaffleId.wrap($rafflesCounter);
        for (uint8 i = 0; i < raffle.rewards.length; i++) {
            Reward memory reward = raffle.rewards[i];
            ERC1155(reward.addy).safeTransferFrom(
                msg.sender,
                address(this),
                reward.tokenId,
                1,
                bytes("")
            );
            $raffles[id].rewards.push(reward);
        }
        $raffles[id].creator = msg.sender;
        $raffles[id].init = raffle.init == 0 ? block.number : raffle.init;
        $raffles[id].deadline = raffle.deadline;
        $raffles[id].ticket.asset = raffle.ticket.asset;
        $raffles[id].ticket.price = raffle.ticket.price;
        $raffles[id].ticket.max = raffle.ticket.max;

        unchecked {
            $rafflesCounter++;
        }

        emit Created(raffle);
    }

    function participate(
        RaffleId id,
        uint256 amount,
        address participant
    ) public {
        Raffle memory raffle = $raffles[id];

        if (block.number < raffle.init) revert NotStartedYet();
        if (block.number > raffle.deadline) revert Ended();

        if ($ticketsCounter[id] + amount > raffle.ticket.max)
            revert NotEnoughTicketsRemaining();

        uint ticketPrice = raffle.ticket.price;
        uint fee = ticketPrice > 100 ? (ticketPrice * FEE) / 10_000 : 0;
        uint amountAfterFee = (amount * raffle.ticket.price) - fee;
        if (fee > 0) ERC20(raffle.ticket.asset).transfer(FEE_RECEIVER, fee);
        ERC20(raffle.ticket.asset).transfer(raffle.creator, amountAfterFee);

        $participants[id].push(
            Participant({addy: participant, tickets: amount})
        );
        $participantIndex[id][participant] = $participants[id].length;

        $ticketsCounter[id] += amount;

        emit BoughtTicket(id, amount, participant);
    }

    function participateWithNative(
        RaffleId id,
        uint256 amount,
        address to
    ) public payable {
        require($raffles[id].ticket.asset == WRAPPED_NATIVE, "wrong asset");
        NativeWrapper(WRAPPED_NATIVE).deposit{value: msg.value}();
        participate(id, amount, to);
    }

    function draw(RaffleId id) public {
        Raffle memory raffle = $raffles[id];

        if (raffle.deadline > block.number) revert InProgress();

        address[] memory winners = WeightedRandom.pickMultiple(
            $participants[id],
            raffle.rewards.length,
            $ticketsCounter[id],
            raffle.deadline
        );

        unchecked {
            uint rewardsToDistributeAmount = raffle.rewards.length -
                (raffle.rewards.length - winners.length);
            uint i = 0;

            for (; i < rewardsToDistributeAmount; i++) {
                Reward memory reward = raffle.rewards[i];
                ERC721(reward.addy).transferFrom(
                    address(this),
                    winners[i],
                    reward.tokenId
                );
            }

            // return rewards not distributed to the raffle creator
            for (; i < raffle.rewards.length; i++) {
                Reward memory reward = raffle.rewards[i];
                ERC721(reward.addy).transferFrom(
                    address(this),
                    raffle.creator,
                    reward.tokenId
                );
            }
        }

        emit Completed(id, winners);
    }

    function balanceOf(
        address participant,
        RaffleId id
    ) public view virtual returns (uint256) {
        uint participantIndex = $participantIndex[id][participant];
        return $participants[id][participantIndex].tickets;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
