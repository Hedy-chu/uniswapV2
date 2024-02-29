// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV2Factory} from "../src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "../src/UniswapV2Pair.sol";
import {NFTMarket} from "../src/NFTMarket.sol";
import {MyERC721} from "../src/MyERC721.sol";
import {UniswapV2Router02} from "../src/UniswapV2Router02.sol";
import {IUniswapV2Pair} from "../src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "../src/interfaces/IUniswapV2Factory.sol";
import {WETH9} from "../src/WETH9.sol";
import "forge-std/mocks/MockERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

contract UniswapV2Test is Test {
    UniswapV2Factory public factory;
    UniswapV2Router02 public router;
    NFTMarket public nftMarket;
    MyERC721 public nft;
    WETH9 public weth;
    MockERC20 public token0;
    MockERC20 public token1;
    address public pair;
    address public alice;
    address public admin;
    address[] path;

    function setUp() public {
        admin = makeAddr("admin");
        alice = makeAddr("alice");

        vm.startPrank(alice);
        {
            factory = new UniswapV2Factory(address(this));
            weth = new WETH9();
            router = new UniswapV2Router02(address(factory), address(weth));

            token0 = new MockERC20();
            token0.initialize("Token0", "TK0", 18);
            token1 = new MockERC20();
            token1.initialize("Token1", "TK1", 18);
            nft = new MyERC721();
            nftMarket = new NFTMarket(
                address(nft),
                weth,
                address(router)
            );
        }
    }

    function testSwap() public {
        vm.startPrank(alice);
        deal(address(token0), alice, 200 ether);
        deal(address(token1), alice, 200 ether);
        path.push(address(token0));
        path.push(address(token1));
        // 非常重要的一步：升级版本后，pair的代码发生变化，UniswapV2Library中的的pairFor方法中的hash值需要更改为a
        bytes32 a = keccak256(type(UniswapV2Pair).creationCode);
        console.logBytes32(a);
        {
            // 授权
            token0.approve(address(router), token0.balanceOf(alice));
            token1.approve(address(router), token1.balanceOf(alice));

            // 添加流动性
            (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(
                address(token0),
                address(token1),
                100 ether,
                100 ether,
                0,
                0,
                address(alice),
                block.timestamp
            );
            console.log("liquidity:", liquidity);
            pair = factory.getPair(address(token0), address(token1));

            router.swapExactTokensForTokens(
                100 ether,
                0,
                path,
                alice,
                block.timestamp
            );
            console.log("alice token1 balance", token1.balanceOf(alice));
            console.log("alice token0 balance", token0.balanceOf(alice));
            console.log(
                "pair token0 balance",
                MockERC20(token0).balanceOf(pair)
            );
            console.log(
                "pair token1 balance",
                MockERC20(token1).balanceOf(pair)
            );
        }
        vm.stopPrank();
    }

    /**
     * 测试用weth买nft
     * 如果是平台币，就是有token => 平台币直接兑换，没有token => weth => 平台币直接兑换
     */
    function testByNft() public {
        deal(address(token0), alice, 200 ether);
        deal(address(token1), alice, 200 ether);
        deal(address(weth), alice, 200 ether);

        deal(address(token0), admin, 200 ether);
        deal(address(token1), admin, 200 ether);
        deal(address(weth), admin, 200 ether);

        vm.startPrank(alice);
     
        path.push(address(token0));
        path.push(address(weth));
        {
            nft.mint(alice);

            // 授权
            nft.approve(address(nftMarket), 0);
            token0.approve(address(router), token0.balanceOf(alice));
            // token1.approve(address(router), token1.balanceOf(alice));
            weth.approve(address(router), token1.balanceOf(alice));

            // 添加流动性
            (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(
                address(token0),
                address(weth),
                100 ether,
                100 ether,
                0,
                0,
                address(alice),
                block.timestamp
            );
            console.log("liquidity:", liquidity);
            pair = factory.getPair(address(token0), address(weth));
            console.log("pair:", pair);
      
            // 上架
            nftMarket.list(0, 1 ether);
            assertTrue(nftMarket.onSale(0));
        }
        vm.stopPrank();

        vm.startPrank(admin);
        {
            // 授权
            token0.approve(address(router), 100 ether);
            // token1.approve(address(router), 100 ether);
            token0.approve(address(nftMarket), 10 ether);
            // 确实购买的代币
            // 如果不是官方指定代币（目前是weth），看有没有 用户代币=> weth
            // 有路径 直接获得token => weth
            // 没有路径 结束,没有流动性
            // 获得储备金
            (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(pair).getReserves();
            // 获得输入的金额
            uint amountIn = router.getAmountIn(nftMarket.listPrice(0), reserve0, reserve1);
            // 设置最大能接受的amountIn ： amountInMax ，作为参数传入buy
            console.log("amountIn:", amountIn);
            // 购买
            nftMarket.buyNft(0, amountIn, amountIn * 12 /10 ,address(token0));
            assertEq(nftMarket.onSale(0), false);
            assertEq(nft.ownerOf(0), address(admin));
        }
    }
}
