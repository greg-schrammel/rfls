// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";
import {ERC721} from "../lib/solady/src/tokens/ERC721.sol";
import {ERC1155} from "../lib/solady/src/tokens/ERC1155.sol";
import {WETH} from "../lib/solady/src/tokens/WETH.sol";

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
    RewardType rewardType;
    uint256 tokenId;
    uint256 amount;
}

struct Ticket {
    uint256 price;
    uint256 max;
    address asset; // usdc, weth
    string uri;
}

struct Raffle {
    address creator;
    address recipient;
    uint256 deadline;
    uint256 init;
    bool completed;
    Ticket ticket;
}

contract Rfls {
    event Created(RaffleId indexed raffleId, address indexed creator);
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

    uint256 public $rafflesCounter = 0;
    mapping(RaffleId => Raffle) public $raffles;
    mapping(RaffleId => Reward[]) public $rewards;

    mapping(RaffleId => address[]) public $participants;
    mapping(RaffleId => mapping(address => uint256)) public $participantTickets;
    mapping(RaffleId => uint256) public $ticketsCounter;

    uint8 public constant FEE = 100;
    address public immutable FEE_RECEIVER;

    address payable immutable WRAPPED_NATIVE;

    constructor(address wrappedNative, address fee_receiver) {
        WRAPPED_NATIVE = payable(wrappedNative);
        FEE_RECEIVER = fee_receiver;
    }

    function _transferReward(
        Reward memory reward,
        address from,
        address to
    ) internal {
        if (reward.rewardType == RewardType.erc721)
            ERC721(reward.addy).transferFrom(from, to, reward.tokenId);
        else if (reward.rewardType == RewardType.erc20) {
            // ew
            if (from == address(this))
                ERC20(reward.addy).transfer(to, reward.amount);
            else ERC20(reward.addy).transferFrom(from, to, reward.amount);
        } else
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
            _transferReward(rewards[i], msg.sender, address(this));
            $rewards[id].push(rewards[i]);
        }
    }

    function create(Raffle memory raffle, Reward[] memory rewards) public {
        if (block.number >= raffle.deadline) revert InvalidDeadline();

        RaffleId id = RaffleId.wrap($rafflesCounter);

        addRewards(id, rewards);
        $raffles[id].creator = msg.sender;
        $raffles[id].recipient = raffle.recipient;
        $raffles[id].init = raffle.init;
        $raffles[id].deadline = raffle.deadline;
        $raffles[id].ticket = raffle.ticket;

        unchecked {
            $rafflesCounter++;
        }

        emit Created(id, raffle.creator);
    }

    function helpCreatorScrewedUp(RaffleId id) public {
        if ($raffles[id].creator != msg.sender) revert NotTheCreator();
        if ($ticketsCounter[id] != 0) revert InProgress();
        delete $raffles[id];

        Reward[] memory rewards = $rewards[id];
        for (uint8 i = 0; i < rewards.length; i++) {
            _transferReward(rewards[i], address(this), msg.sender);
        }
    }

    function participate(
        RaffleId id,
        uint256 amount,
        address participant
    ) public {
        Raffle memory raffle = $raffles[id];

        if (block.number < raffle.init) revert NotStartedYet();
        if (block.number >= raffle.deadline) revert Ended();

        unchecked {
            uint ticketsCounter = $ticketsCounter[id] + amount;
            $ticketsCounter[id] = ticketsCounter;
            if (ticketsCounter > raffle.ticket.max)
                revert NotEnoughTicketsRemaining();

            uint256 ticketPrice = raffle.ticket.price;
            uint256 fee = ticketPrice > 100 ? (ticketPrice * FEE) / 10_000 : 0;
            uint256 amountAfterFee = (amount * ticketPrice) - fee;

            ERC20 asset = ERC20(raffle.ticket.asset);
            if (fee > 0) asset.transferFrom(participant, FEE_RECEIVER, fee);
            asset.transferFrom(participant, raffle.recipient, amountAfterFee);

            $participantTickets[id][participant] += amount;
            $participants[id].push(participant);
        }

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
        WETH(WRAPPED_NATIVE).deposit{value: msg.value}();
        participate(id, amount, to);
    }

    function _weightedRandom(
        address[] memory participants,
        mapping(address => uint256) storage weights,
        uint256 seed,
        uint256 weightsSum,
        uint256 max
    ) internal returns (address[] memory) {
        if (weightsSum == 0) return new address[](0);

        address[] memory winners = new address[](max);

        unchecked {
            for (uint256 i = 0; i < max; i++) {
                uint random = seed % weightsSum;
                for (
                    uint256 winnerIndex = 0;
                    winnerIndex < participants.length;
                    winnerIndex++
                ) {
                    address winner = participants[winnerIndex];
                    uint weight = weights[winner];
                    if (random < weight) {
                        winners[i] = winner;

                        // remove the winner ticket
                        weights[winner] -= 1;
                        weightsSum -= 1;

                        // if the participant has no more tickets remove him
                        if (weights[winner] == 0) {
                            uint lastIndex = participants.length - 1;
                            participants[winnerIndex] = participants[lastIndex];
                            delete participants[lastIndex];

                            if (lastIndex == 0) return winners;
                        }

                        break;
                    }
                    random -= weight;
                }
            }
        }
        return winners;
    }

    function draw(RaffleId id) public {
        Raffle memory raffle = $raffles[id];
        $raffles[id].completed = true;
        if (raffle.completed == true) revert AlreadyCompleted();
        if (block.number <= raffle.deadline) revert InProgress();

        Reward[] memory rewards = $rewards[id];

        address[] memory winners = _weightedRandom(
            $participants[id],
            $participantTickets[id],
            uint256(
                blockhash(
                    block.number - raffle.deadline > 254 ? 255 : raffle.deadline
                )
            ),
            $ticketsCounter[id],
            rewards.length
        );

        unchecked {
            uint i = 0;

            for (; i < winners.length; i++) {
                _transferReward(rewards[i], address(this), winners[i]);
            }

            // return rewards not distributed to the raffle creator
            for (; i < rewards.length; i++) {
                _transferReward(rewards[i], address(this), raffle.creator);
            }
        }

        emit Completed(id, winners);
    }

    function balanceOf(
        address participant,
        RaffleId id
    ) public view returns (uint256) {
        return $participantTickets[id][participant];
    }

    function uri(RaffleId id) public view returns (string memory) {
        return $raffles[id].ticket.uri;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
