// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Pair} from "../src/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "../src/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FlashSwap is Ownable {
    address public factoryA;
    address public pairA;
    address public routerA;
    address public factoryB;
    address public pairB;
    address public routerB;
    address public token0;
    address public token1;
    using SafeERC20 for IERC20;

    constructor(
        address _factoryA,
        address _routerA,
        address _factoryB,
        address _routerB,
        address _token0,
        address _token1
    ) Ownable(msg.sender) {
        factoryA = _factoryA;
        routerA = _routerA;
        factoryB = _factoryB;
        routerB = _routerB;
        token0 = _token0;
        token1 = _token1;
    }

    function flash() public {
        console.log("Flash swap started");
        pairA = IUniswapV2Factory(factoryA).getPair(
            address(token0),
            address(token1)
        );
        address test = IUniswapV2Pair(pairA).token0();

        console.log("pairA", pairA);
        console.log("test", test);

        IUniswapV2Pair(pairA).swap(
            0,
            1 ether,
            address(this),
            abi.encode(address(token1), 1 ether)
        );
    }

    // 闪电贷回调函数，只能被 KK/WETH pair 合约调用
    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external {
        console.log("amount1", amount1);
        pairA = IUniswapV2Factory(factoryA).getPair(token0, token1);
        // 确保调用者是 V2 pair 合约
        assert(msg.sender == pairA); // ensure that msg.sender is a V2 pair

        // 解码calldata
        (address tokenBorrow, uint256 borrowAmount) = abi.decode(
            data,
            (address, uint256)
        );

        console.log(
            "FlashSwap: uniswapV2Call called by, tokenBorrow:, borrowAmount:",
            msg.sender,
            tokenBorrow,
            borrowAmount
        );

        // 借的是token1
        require(tokenBorrow == token1, "token borrow != token1");

        address[] memory path = new address[](2);
        path[0] = token1;
        path[1] = token0;

        uint balance = IERC20(tokenBorrow).balanceOf(address(this));
        console.log("balance:", balance);

        IERC20(token1).approve(routerB, borrowAmount);
        // flashloan 逻辑，weth => KK
        console.log("weth => KK start");
        uint[] memory amounts = IUniswapV2Router02(routerB)
            .swapExactTokensForTokens(
                borrowAmount,
                0,
                path,
                address(this),
                block.timestamp
            );
        uint KKAmount = amounts[amounts.length - 1];
        console.log("KKAmount", KKAmount);
        console.log("weth => KK finish");

        console.log("flash amount KK", IERC20(token0).balanceOf(address(this)));
        console.log("pairA balance KK", IERC20(token0).balanceOf(pairA));
        
        //更改路径
        path[0] = token0;
        path[1] = token1;

        // amountIn中包含fee
        uint[] memory amountIns = IUniswapV2Router02(routerA).getAmountsIn(
            amount1,
            path
        );
        uint backKKAmount = amountIns[0];

        console.log("back", backKKAmount);

        // 归还闪电贷 KK
        IERC20(token0).safeTransfer(address(pairA), backKKAmount);

        console.log("amount KK after", IERC20(token0).balanceOf(address(this)));
        console.log(
            "amount token1 after",
            IERC20(token1).balanceOf(address(this))
        );
    }

    /**
     * 提取KK
     */
    function withDrawKK() public onlyOwner {
        require(
            IERC20(token0).balanceOf(address(this)) > 0,
            "KK balance is zero"
        );
        IERC20(token0).safeTransfer(
            msg.sender,
            IERC20(token0).balanceOf(address(this))
        );
    }
}
