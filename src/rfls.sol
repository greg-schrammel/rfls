// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "./erc20.sol";

interface ERC721 {
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external payable;
}

interface IWETH {
    function deposit() external payable;

    function withdraw(uint) external;
}

error Ended();
error InProgress();
error InvalidDeadline();
error NotEnoughTicketsRemaining();

type RaffleId is uint256;
type Blocknumber is uint256;

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
    Blocknumber deadline;
    Blocknumber init;
}

struct Participant {
    address addy;
    uint256 tickets;
}

contract rfls {
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
    uint256 $rafflesCounter = 0;

    uint8 constant FEE = 100;
    address immutable FEE_RECEIVER;

    address immutable WETH;

    constructor(address _WETH, address _FEE_RECEIVER) {
        WETH = _WETH;
        FEE_RECEIVER = _FEE_RECEIVER;
    }

    function create(Raffle memory raffle) public {
        if (Blocknumber.unwrap(raffle.deadline) > block.number)
            revert InvalidDeadline();

        for (uint8 i = 0; i <= raffle.rewards.length; ++i) {
            Reward memory reward = raffle.rewards[i];
            ERC721(reward.addy).transferFrom(
                msg.sender,
                address(this),
                reward.tokenId
            );
        }

        raffle.creator = msg.sender;
        raffle.init = Blocknumber.unwrap(raffle.init) == 0
            ? Blocknumber.wrap(block.number)
            : raffle.init;
        $raffles[RaffleId.wrap($rafflesCounter)] = raffle;
        unchecked {
            $rafflesCounter++;
        }

        emit Created(raffle);
    }

    function buyTicket(RaffleId id, uint256 amount, address to) public {
        Raffle memory raffle = $raffles[id];
        if (block.number > Blocknumber.unwrap(raffle.deadline)) revert Ended();

        if ($ticketsCounter[id] + amount > raffle.ticket.max)
            revert NotEnoughTicketsRemaining();

        if (raffle.ticket.price > 100) {
            // just so we don't underflow here
            ERC20(raffle.ticket.asset).transfer(
                FEE_RECEIVER,
                (raffle.ticket.price * FEE) / 10_000
            );
        }
        ERC20(raffle.ticket.asset).transfer(
            raffle.creator,
            amount * raffle.ticket.price
        );

        $participants[id].push(Participant({addy: to, tickets: amount}));
        $participantIndex[id][to] = $participants[id].length;

        $ticketsCounter[id] += amount;

        emit BoughtTicket(id, amount, to);
    }

    function buyTicketEth(
        RaffleId id,
        uint256 amount,
        address to
    ) public payable {
        require($raffles[id].ticket.asset == WETH, "wrong asset");
        IWETH(WETH).deposit{value: msg.value}();
        buyTicket(id, amount, to);
    }

    function pickWinner(
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

    function pickWinners(
        uint256 random,
        Participant[] memory participants,
        uint256 maxWinners
    ) internal pure returns (address[] memory) {
        address[] memory winners = new address[](maxWinners);
        unchecked {
            for (uint256 i = 0; i < maxWinners; i++) {
                uint256 winnerIndex = pickWinner(random, participants);
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

    function draw(RaffleId id) public {
        Raffle memory raffle = $raffles[id];
        uint deadline = Blocknumber.unwrap(raffle.deadline);

        if (deadline > block.number) revert InProgress();

        uint256 weightsSum = $ticketsCounter[id];

        uint256 random = uint256(
            // can wait until the result is favorable? yes
            // but anyone can call while you waiting hopefully a bot will call right at the deadline
            blockhash(block.number - deadline > 254 ? 254 : deadline)
            // random must be less than weightsSum
        ) % weightsSum;

        address[] memory winners = pickWinners(
            random,
            $participants[id],
            raffle.rewards.length
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
}
