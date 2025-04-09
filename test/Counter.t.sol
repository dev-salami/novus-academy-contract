// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
// import {SlidingPuzzleGame} from "../src/core.sol";
import {Puzzle} from "../src/core-single.sol";

contract CoreScript is Script {
    function run() public {
        uint256 privateKey = vm.envUint("DEV_PRIVATE_KEY");
        address account = vm.addr(privateKey);
        console.log("Account : ", account);
        vm.startBroadcast(privateKey);

        Puzzle game = new Puzzle();
        // game.createGame(SlidingPuzzleGame.GameMode.SINGLE);

        vm.stopBroadcast();
    }
}
