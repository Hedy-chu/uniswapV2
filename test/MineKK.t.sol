// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MineKK} from "../src/MineKK.sol";
import {KKToken} from "../src/KKToken.sol";
import {WETH9} from "../src/WETH9.sol";
import "forge-std/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract MineKKTest is Test {
    address admin;
    address alice;
    address bob;
    MineKK mineKK;
    KKToken kkToken;
    WETH9 weth;

    function setUp() public {
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        weth = new WETH9();
        mineKK = new MineKK(address(weth));
        kkToken = new KKToken(address(mineKK));
        mineKK.setkkAddress(address(kkToken));
    }

    function testStake() public {
        deal(address(weth), alice, 1000 ether);
        deal(address(weth), bob, 1000 ether);
        vm.startPrank(alice);
        {
            vm.roll(10);
            weth.approve(address(mineKK), 1000 ether);
            mineKK.stake(5 ether);
            console.log("111",mineKK.currentStakeInterest());
            vm.roll(20);
            mineKK.stake(10 ether);
            (
                uint256 stakeAmount,
                uint256 reward,
                uint256 stakeBlock,
                uint stakeInterest
            ) = mineKK.stakeMap(address(alice));
            console.log("222",mineKK.currentStakeInterest());

            // console.log("alice's staked amount:", stakeAmount/1 ether);
            // console.log("alice's reward:", reward / 1 ether);
        }
        vm.stopPrank();

        vm.startPrank(bob);
        {
            vm.roll(30);
            weth.approve(address(mineKK), 1000 ether);
            mineKK.stake(40 ether);
            console.log("333",mineKK.currentStakeInterest());


        }
        vm.stopPrank();

        vm.startPrank(alice);
        {
             vm.roll(40);
             mineKK.unStake(5 ether,false);
             (
                uint256 stakeAmount,
                uint256 reward,
                uint256 stakeBlock,
                uint stakeInterest
            ) = mineKK.stakeMap(address(alice));
            console.log("alice's staked amount:", stakeAmount/1 ether);
            console.log("alice's reward:", reward / 1 ether);
            console.log("444",mineKK.currentStakeInterest());

        }

         vm.startPrank(bob);
        {
            vm.roll(50);
            mineKK.unStake(5 ether,false);

            (
                uint256 stakeAmount,
                uint256 reward,
                uint256 stakeBlock,
                uint stakeInterest
            ) = mineKK.stakeMap(address(bob));
            console.log("bob's staked amount:", stakeAmount/1 ether);
            console.log("bob's reward:", reward / 1 ether);
            console.log("555",mineKK.currentStakeInterest());

        }
        vm.stopPrank();

    }
}
