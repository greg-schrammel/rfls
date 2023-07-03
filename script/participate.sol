// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../lib/forge-std/src/Script.sol";
import {Raffle, RewardType, RaffleId, Reward, Ticket, Rfls} from "../src/rfls.sol";
import {_ERC20} from "../test/mocks/erc20.sol";

contract Participate is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("pk");
        vm.startBroadcast(deployerPrivateKey);

        address addy = 0xBE9EC74186013E8c7054cB75b369478B1bFC372E;

        Rfls rfls = Rfls(0xe953D0E25FaeA26e4A1D1e2ba7b0C7E6FFA6cf8F);
        RaffleId id = RaffleId.wrap(0);

        Ticket memory ticket;
        (, , , , , ticket) = rfls.$raffles(id);
        _ERC20(ticket.asset).approve(address(rfls), ticket.price * 2);
        rfls.participate(id, 2, addy);

        vm.stopBroadcast();
    }
}

// forge script Participate --rpc-url "https://testnet.rpc.zora.co/" --broadcast -vvvv
