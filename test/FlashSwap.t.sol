// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {UniswapV2Router02} from "../src/UniswapV2Router02.sol";
import {FlashSwap} from "../src/FlashSwap.sol";
import {IUniswapV2Pair} from "../src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "../src/interfaces/IUniswapV2Factory.sol";
import {WETH9} from "../src/WETH9.sol";
import "forge-std/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract FlashSwapTest is Test {
    UniswapV2Factory public factoryA;
    UniswapV2Factory public factoryB;
    address public pairA;
    UniswapV2Router02 public routerA;
    UniswapV2Router02 public routerB;
    FlashSwap public flashSwap;
    MockERC20 public token0;
    MockERC20 public token1;
    WETH9 public weth;

    address admin = makeAddr("admin");
    address alice = makeAddr("alice");

    function setUp() public {
        vm.startPrank(admin);
        {
            weth = new WETH9();
            factoryA = new UniswapV2Factory(admin);
            factoryB = new UniswapV2Factory(admin);
            routerA = new UniswapV2Router02(address(factoryA), address(weth));
            routerB = new UniswapV2Router02(address(factoryB), address(weth));
            
            token0 = new MockERC20();
            token0.initialize("Token0", "TK0", 18);
            token1 = new MockERC20();
            token1.initialize("Token1", "TK1", 18);
            flashSwap = new FlashSwap(
                address(factoryA),
                address(routerA),
                address(factoryB),
                address(routerB),
                address(token0),
                address(token1)
            );
        }
        vm.stopPrank();
    }

    // function testFlashSwap() public {
    //     deal(address(token0), alice, 200000 ether);
    //     deal(address(token1), alice, 2000 ether);
    //     vm.startPrank(alice);
    //     {
    //         console.log("alice token0 balance:", token0.balanceOf(alice));
    //         console.log("alice token1 balance:", token1.balanceOf(alice));
    //         token0.approve(address(routerA), 1000 ether);
    //         token0.approve(address(routerB), 100000 ether);
    //         token1.approve(address(routerA), 1000 ether);
    //         token1.approve(address(routerB), 1000 ether);

    //         routerA.addLiquidity(
    //             address(token0),
    //             address(token1),
    //             500 ether,
    //             500 ether,
    //             0,
    //             0,
    //             alice,
    //             block.timestamp
    //         );
    //         pairA = IUniswapV2Factory(factoryA).getPair(
    //             address(token0),
    //             address(token1)
    //         );

    //         routerB.addLiquidity(
    //             address(token0),
    //             address(token1),
    //             50000 ether,
    //             500 ether,
    //             0,
    //             0,
    //             alice,
    //             block.timestamp
    //         );

    //         // flashSwap.flash();
    //         console.log("Flash swap started");
        
    //         pairA = IUniswapV2Factory(factoryA).getPair(
    //                 address(token0),
    //                 address(token1)
    //             );
    //         address test = IUniswapV2Pair(pairA).token0();
            
    //         console.log("pairA",pairA);
    //         console.log("test",test);

    //         IUniswapV2Pair(pairA).swap(
    //             0,
    //             100 ether,
    //             address(flashSwap),
    //             abi.encode(address(token1), 100 ether)
    //         );
    //     }

        function testFlashSwap() public {
        deal(address(token0), alice, 200000 ether);
        deal(address(token1), alice, 2000 ether);
        vm.startPrank(alice);
        {
            console.log("alice token0 balance:", token0.balanceOf(alice));
            console.log("alice token1 balance:", token1.balanceOf(alice));
            token0.approve(address(routerA), 1000 ether);
            token0.approve(address(routerB), 100000 ether);
            token1.approve(address(routerA), 1000 ether);
            token1.approve(address(routerB), 1000 ether);

            routerA.addLiquidity(
                address(token0),
                address(token1),
                500 ether,
                500 ether,
                0,
                0,
                alice,
                block.timestamp
            );
            pairA = IUniswapV2Factory(factoryA).getPair(
                address(token0),
                address(token1)
            );

            routerB.addLiquidity(
                address(token0),
                address(token1),
                50000 ether,
                500 ether,
                0,
                0,
                alice,
                block.timestamp
            );

            flashSwap.flash();
            
        }
        
        vm.stopPrank();
    }
}
