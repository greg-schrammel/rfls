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
    event URI(string value, uint256 indexed id);

    uint256 public $rafflesCounter = 0;
    mapping(RaffleId => Raffle) public $raffles;
    mapping(RaffleId => Reward[]) public $rewards;

    mapping(RaffleId => address[]) public $participants;
    mapping(RaffleId => mapping(address => uint256)) public $participantTickets;
    mapping(RaffleId => uint256) public $ticketsCounter;

    uint8 public constant FEE = 100;
    address public immutable FEE_RECEIVER;
    address public immutable OWNER;

    string fallbackUri;

    address payable immutable WRAPPED_NATIVE;

    constructor(address wrappedNative, address fee_receiver, address owner) {
        WRAPPED_NATIVE = payable(wrappedNative);
        FEE_RECEIVER = fee_receiver;
        OWNER = owner;
    }

    function _transferReward(
        Reward memory reward,
        address from,
        address to
    ) internal {
        if (reward.rewardType == RewardType.erc721)
            return ERC721(reward.addy).transferFrom(from, to, reward.tokenId);

        if (reward.rewardType == RewardType.erc20) {
            ERC20 token = ERC20(reward.addy);
            if (from == address(this)) token.transfer(to, reward.amount);
            else token.transferFrom(from, to, reward.amount);
            return;
        }

        return
            ERC1155(reward.addy).safeTransferFrom(
                from,
                to,
                reward.tokenId,
                reward.amount,
                bytes("")
            );
    }

    function addRewards(RaffleId id, Reward[] memory rewards) public {
        uint l = rewards.length;
        unchecked {
            for (uint256 i = 0; i < l; ++i) {
                _transferReward(rewards[i], msg.sender, address(this));
                $rewards[id].push(rewards[i]);
            }
        }
    }

    function create(Raffle calldata raffle, Reward[] memory rewards) public {
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
        unchecked {
            for (uint i = 0; i < rewards.length; i++) {
                _transferReward(rewards[i], address(this), msg.sender);
            }
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

        Ticket memory ticket = raffle.ticket;
        unchecked {
            if (($ticketsCounter[id] += amount) > ticket.max)
                revert NotEnoughTicketsRemaining();

            uint256 price = ticket.price;
            uint256 fee = price > 100 ? (price * FEE) / 10_000 : 0;
            uint256 amountAfterFee = (amount * price) - fee;

            ERC20 asset = ERC20(ticket.asset);
            if (fee > 0) asset.transferFrom(participant, FEE_RECEIVER, fee);
            asset.transferFrom(participant, raffle.recipient, amountAfterFee);

            $participantTickets[id][participant] += amount;
            $participants[id].push(participant);
        }

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

        uint participantsLength = participants.length;
        unchecked {
            for (uint256 i = 0; i < max; i++) {
                uint random = seed % weightsSum;
                for (
                    uint256 winnerIndex = 0;
                    winnerIndex < participantsLength;
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
                            uint lastIndex = participantsLength - 1;
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
        uint rewardsLength = rewards.length;

        uint256 seed = uint256(blockhash(raffle.deadline));
        if (seed == 0) seed = uint256(blockhash(block.number - 255));

        address[] memory winners = _weightedRandom(
            $participants[id],
            $participantTickets[id],
            seed,
            $ticketsCounter[id],
            rewardsLength
        );

        unchecked {
            uint i = 0;

            for (; i < winners.length; i++) {
                _transferReward(rewards[i], address(this), winners[i]);
            }

            // return rewards not distributed to the raffle creator
            for (; i < rewardsLength; i++) {
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

    function setFallbackUri(string calldata _uri) external {
        if (msg.sender != OWNER) return;
        fallbackUri = _uri;
    }

    function uri(RaffleId id) public view returns (string memory _uri) {
        _uri = $raffles[id].ticket.uri;
        if (bytes(_uri).length == 0) _uri = fallbackUri;
    }

    function name() public pure returns (string memory) {
        return "Raffle Ticket";
    }

    function symbol() public pure returns (string memory) {
        return unicode"🎟️";
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual returns (bool result) {
        assembly {
            let s := shr(224, interfaceId)
            // ERC165: 0x01ffc9a7, ERC1155MetadataURI: 0x0e89341c.
            // not (ERC1155: 0xd9b67a26) because it's not fully
            result := or(eq(s, 0x01ffc9a7), eq(s, 0x0e89341c))
        }
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
