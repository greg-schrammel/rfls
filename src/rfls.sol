// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ERC721 {
    function transferFrom(
        address _from,
        address _to,
        uint256 _tokenId
    ) external payable;
}

interface ERC20 {
    function transfer(
        address _to,
        uint256 _value
    ) external returns (bool success);

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) external returns (bool success);
}

error Ended();
error InProgress();

type RaffleId is uint256;
type BlockNumber is uint256;

struct Reward {
    address addy;
    uint256 tokenId;
}

struct Ticket {
    address asset; // usdc, weth
    uint256 price;
}

struct Raffle {
    address creator;
    Ticket ticket;
    Reward[] rewards;
    BlockNumber deadline;
}

struct Participant {
    address addy;
    uint256 tickets;
}

contract rfls {
    event Created(
        address indexed creator,
        BlockNumber indexed deadline,
        Reward[] indexed rewards
    );
    event Completed(RaffleId indexed raffle, address[] indexed winners);
    event BoughtTicket(
        RaffleId indexed raffle,
        uint256 amount,
        address indexed to
    );

    mapping(RaffleId => Raffle) $raffles;
    mapping(RaffleId => Participant[]) $participants;
    mapping(RaffleId => mapping(address => uint256)) $participantIndex;
    mapping(RaffleId => uint256) $ticketsCounter;
    uint256 $rafflesCounter = 0;

    uint8 constant FEE = 100;

    function create(
        Reward[] calldata rewards,
        Ticket calldata ticket,
        BlockNumber deadline
    ) public {
        for (uint8 i = 0; i <= rewards.length; ++i) {
            Reward calldata reward = rewards[i];
            ERC721(reward.addy).transferFrom(
                msg.sender,
                address(this),
                reward.tokenId
            );
        }

        $raffles[RaffleId.wrap($rafflesCounter)] = Raffle({
            creator: msg.sender,
            deadline: deadline,
            rewards: rewards,
            ticket: ticket
        });
        unchecked {
            $rafflesCounter++;
        }

        emit Created(msg.sender, deadline, rewards);
    }

    function buyTicket(RaffleId id, uint256 amount, address to) public {
        Raffle memory raffle = $raffles[id];
        if (block.number > BlockNumber.unwrap(raffle.deadline)) revert Ended();

        if (raffle.ticket.price > 100) {
            // just so we don't underflow here
            ERC20(raffle.ticket.asset).transfer(
                address(this),
                (raffle.ticket.price * FEE) / 10_000
            );
        }
        ERC20(raffle.ticket.asset).transfer(to, amount * raffle.ticket.price);

        $participants[id].push(Participant({addy: to, tickets: amount}));
        $participantIndex[id][to] = $participants[id].length;

        $ticketsCounter[id] += amount;

        emit BoughtTicket(id, amount, to);
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
        uint deadline = BlockNumber.unwrap(raffle.deadline);

        if (deadline > block.number) revert InProgress();

        uint256 weightsSum = $ticketsCounter[id];
        // random must be less than weightsSum

        // can wait until the result is favorable? yes
        // but anyone can call while you waiting hopefully a bot will call right at the deadline
        uint256 random = uint256(
            blockhash(block.number - deadline > 254 ? 254 : deadline)
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
