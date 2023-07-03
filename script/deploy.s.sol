// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Script.sol";
import {Raffle, RewardType, RaffleId, Reward, Ticket, Rfls} from "../src/rfls.sol";
import {_ERC20} from "../test/mocks/erc20.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("pk");
        vm.startBroadcast(deployerPrivateKey);

        address addy = 0xBE9EC74186013E8c7054cB75b369478B1bFC372E;

        Rfls rfls = new Rfls(addy, addy, addy);

        _ERC20 token = new _ERC20(100 ether);
        token.approve(address(rfls), 10 ether);

        string memory uri = "https://avatars.githubusercontent.com/u/6232729";

        Reward[] memory rewards = new Reward[](1);
        rewards[0] = Reward({
            addy: address(token),
            tokenId: 1,
            amount: 10 ether,
            rewardType: RewardType.erc20
        });

        Raffle memory raffle = Raffle({
            ticket: Ticket(1 ether, 100, address(token), uri),
            deadline: block.number + 10_000,
            init: 0,
            creator: address(0),
            recipient: addy,
            completed: false
        });

        rfls.create(raffle, rewards);

        vm.stopBroadcast();
    }
}

// forge script Deploy --rpc-url "https://testnet.rpc.zora.co/" --broadcast -vvvv
