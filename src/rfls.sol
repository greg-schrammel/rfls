// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

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
error NotTheCreator();
error InvalidDeadline();
error NotEnoughTicketsRemaining();
error AlreadyCompleted();

type RaffleId is uint256;

enum RewardType {
    erc1155,
    erc721,
    erc20
}

struct Reward {
    address addy;
    uint256 tokenId;
    uint256 amount;
    RewardType rewardType;
}

struct Ticket {
    address asset; // usdc, weth
    uint256 price;
    uint256 max;
}

struct Raffle {
    address creator;
    address recipient;
    Ticket ticket;
    Reward[] rewards;
    uint256 deadline;
    uint256 init;
    bool completed;
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

    function updateParticipants(
        Participant[] memory participants,
        uint winnerIndex
    ) internal pure returns (Participant[] memory) {
        // remove the winner ticket
        participants[winnerIndex].tickets -= 1;

        // if the participant has no more tickets remove him
        if (participants[winnerIndex].tickets == 0) {
            participants[winnerIndex] = participants[participants.length - 1];
            delete participants[participants.length - 1];
        }

        return participants;
    }

    function pickMultiple(
        Participant[] memory participants,
        uint256 random,
        uint256 weightsSum,
        uint256 max
    ) internal pure returns (address[] memory) {
        address[] memory winners = new address[](max);
        unchecked {
            for (uint256 i = 0; i < max; i++) {
                uint256 winnerIndex = pickOne(
                    random % weightsSum,
                    participants
                );
                winners[i] = participants[winnerIndex].addy;
                participants = updateParticipants(participants, winnerIndex);
                weightsSum -= 1;
                if (participants.length == 0) return winners;
            }
        }
        return winners;
    }
}

contract Rfls {
    event Created(Raffle indexed raffle);
    event Completed(RaffleId indexed raffle, address[] indexed winners);
    event Participate(
        RaffleId indexed raffle,
        uint256 indexed tickets,
        address indexed participant
    );
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    mapping(RaffleId => Raffle) public $raffles;
    mapping(RaffleId => Participant[]) public $participants;
    mapping(RaffleId => mapping(address => uint256)) $participantIndex;
    mapping(RaffleId => uint256) public $ticketsCounter;
    uint256 public $rafflesCounter = 0;

    uint8 public constant FEE = 100;
    address public immutable FEE_RECEIVER;

    address immutable WRAPPED_NATIVE;

    constructor(address wrappedNative, address fee_receiver) {
        WRAPPED_NATIVE = wrappedNative;
        FEE_RECEIVER = fee_receiver;
    }

    function getParticipants(
        RaffleId id
    ) public view returns (Participant[] memory) {
        return $participants[id];
    }

    function _transferReward(
        Reward memory reward,
        address from,
        address to
    ) internal {
        if (reward.rewardType == RewardType.erc721)
            ERC721(reward.addy).transferFrom(from, to, reward.tokenId);
        else if (reward.rewardType == RewardType.erc20)
            ERC20(reward.addy).transferFrom(from, to, reward.amount);
        else
            ERC1155(reward.addy).safeTransferFrom(
                from,
                to,
                reward.tokenId,
                reward.amount,
                bytes("")
            );
    }

    function addRewards(RaffleId id, Reward[] memory rewards) public {
        for (uint8 i = 0; i < rewards.length; i++) {
            Reward memory reward = rewards[i];
            _transferReward(reward, msg.sender, address(this));
            $raffles[id].rewards.push(reward);
        }
    }

    function create(Raffle memory raffle) public {
        if (block.number > raffle.deadline) revert InvalidDeadline();

        RaffleId id = RaffleId.wrap($rafflesCounter);

        addRewards(id, raffle.rewards);
        $raffles[id].creator = msg.sender;
        $raffles[id].recipient = raffle.recipient;
        $raffles[id].init = raffle.init;
        $raffles[id].deadline = raffle.deadline;
        $raffles[id].ticket = raffle.ticket;

        unchecked {
            $rafflesCounter++;
        }

        emit Created(raffle);
    }

    function helpCreatorScrewedUp(RaffleId id) public {
        if ($raffles[id].creator != msg.sender) revert NotTheCreator();
        if ($ticketsCounter[id] != 0) revert InProgress();
        $raffles[id].completed = true;

        Raffle memory raffle = $raffles[id];
        for (uint8 i = 0; i < raffle.rewards.length; i++) {
            _transferReward(raffle.rewards[i], address(this), msg.sender);
        }
    }

    function participate(
        RaffleId id,
        uint256 amount,
        address participant
    ) public {
        Raffle memory raffle = $raffles[id];

        if (block.number < raffle.init) revert NotStartedYet();
        if (block.number > raffle.deadline) revert Ended();
        if (raffle.completed == true) revert AlreadyCompleted();
        if ($ticketsCounter[id] + amount > raffle.ticket.max)
            revert NotEnoughTicketsRemaining();

        uint ticketPrice = raffle.ticket.price;
        uint fee = ticketPrice > 100 ? (ticketPrice * FEE) / 10_000 : 0;
        uint amountAfterFee = (amount * ticketPrice) - fee;
        if (fee > 0)
            ERC20(raffle.ticket.asset).transferFrom(
                participant,
                FEE_RECEIVER,
                fee
            );
        ERC20(raffle.ticket.asset).transferFrom(
            participant,
            raffle.recipient,
            amountAfterFee
        );

        $participants[id].push(Participant(participant, amount));
        $participantIndex[id][participant] = $participants[id].length - 1;

        $ticketsCounter[id] += amount;

        emit Participate(id, amount, participant);

        emit TransferSingle(
            address(this),
            address(this),
            participant,
            RaffleId.unwrap(id),
            amount
        );
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

        $raffles[id].completed = true;
        if (raffle.completed == true) revert AlreadyCompleted();

        if (raffle.deadline > block.number) revert InProgress();

        uint256 randomSample = uint256(
            blockhash(
                block.number - raffle.deadline > 254 ? 255 : raffle.deadline
            )
        );

        address[] memory winners = WeightedRandom.pickMultiple(
            $participants[id],
            randomSample,
            $ticketsCounter[id],
            raffle.rewards.length
        );

        unchecked {
            uint rewardsToDistributeAmount = raffle.rewards.length -
                (raffle.rewards.length - winners.length);
            uint i = 0;

            for (; i < rewardsToDistributeAmount; i++) {
                Reward memory reward = raffle.rewards[i];
                _transferReward(reward, address(this), winners[i]);
            }

            // return rewards not distributed to the raffle creator
            for (; i < raffle.rewards.length; i++) {
                Reward memory reward = raffle.rewards[i];
                _transferReward(reward, address(this), raffle.creator);
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
