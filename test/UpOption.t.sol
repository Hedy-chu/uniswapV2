// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UpOption} from "../src/UpOption.sol";
import {KKToken} from "../src/KKToken.sol";
import {WETH9} from "../src/WETH9.sol";
import "forge-std/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract UpOptionTest is Test {
    address public admin;
    address public alice;
    UpOption public upOption;
    KKToken public kkToken;

    function setUp() public {
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        vm.startPrank(admin);
        {
            kkToken = new KKToken(address(admin));
            vm.warp(100);
            upOption = new UpOption(address(kkToken),100,block.timestamp+10,3000 ether);
        }
        vm.stopPrank();  
    }

    function testUpOption() public {
        deal(admin,100 ether);
        // 发行
        vm.startPrank(admin);
        {
            upOption.issueOptions{value:1 ether}();
            upOption.approve(address(upOption),upOption.balanceOf(admin));
            assertEq(upOption.balanceOf(admin),1 ether);
            console.log("issue 1 ether Option");
        }
        vm.stopPrank();

        deal(address(kkToken),alice,100000 ether);
        vm.startPrank(alice);
        {
            // 100KK,购买期权
            kkToken.approve(address(upOption),100);
            upOption.buyOption(0.5 ether, upOption.optionPrice());
            assertEq(upOption.balanceOf(alice),0.5 ether);

            console.log("buy 0.5 ether Option");

            // 执行期权
            vm.warp(2000);
            kkToken.approve(address(upOption),4000 ether);
            upOption.exerciseOption(upOption.strikePrice(),upOption.balanceOf(alice));
            uint ethbalance = address(alice).balance;
            assertEq(ethbalance ,0.5 ether);
            console.log("exercise 0.5 ether Option");
        }
        vm.stopPrank();

        vm.startPrank(admin);
        {
            vm.warp(2000);
            upOption.burnOptions();
            console.log("burn  Option");
        }
        vm.stopPrank();



    }
}