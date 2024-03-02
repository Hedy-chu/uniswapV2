// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswapV2Router02.sol";

interface IInscribeERC20 {
    function init(string memory name, string memory symbol) external;

    function inscribe(address to, uint256 amount) external;

    function balanceOf(address account) external returns (uint256);

    function totalSupply() external returns (uint256);

    function decimals() external returns (uint8);
}

contract InscribeFactory is Ownable {
    using Clones for address;
    using SafeERC20 for IERC20;
    address tokenAddr;
    address public router;
    address public weth;
    mapping(address => uint256) public _perMint;
    mapping(address => uint256) public _maxInscribe;
    mapping(address => uint256) public _fee;

    constructor(
        address addr,
        address routerAddr,
        address wethAddr
    ) Ownable(msg.sender) {
        tokenAddr = addr;
        router = routerAddr;
        weth = wethAddr;
    }

    modifier checkMaxInscribe(address insAddr) {
        require(
            IInscribeERC20(insAddr).totalSupply() + _perMint[insAddr] * 2 <=
                _maxInscribe[insAddr],
            "maxInscribe"
        );
        _;
    }

    function depolyInscription(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 perMint,
        uint256 fee
    ) public returns (address) {
        require(totalSupply > perMint, "totalSupply must bigger than perMint");
        require(
            totalSupply % (perMint * 2) == 0,
            "totalSupply % (perMint*2) must equalis 0"
        );

        address newAddress = tokenAddr.clone();
        IInscribeERC20(newAddress).init(name, symbol);
        _perMint[newAddress] = perMint;
        _maxInscribe[newAddress] = totalSupply / 2;
        _fee[newAddress] = fee;

        return newAddress;
    }

    /**
     * 打铭文
     * 1. 一半铸造给用户
     * 2. 一半铸造给项目方
     * 3. 收取的gas一半用于和铭文加入到DEX用于提供流动性
     * @param insAddr 铭文地址
     */
    function mintInscription(
        address insAddr,
        uint256 amount
    ) public payable checkMaxInscribe(insAddr) {
        require(amount == _fee[insAddr], "amount must equal fee");
        uint256 perMint = _perMint[insAddr];
        IInscribeERC20(insAddr).inscribe(msg.sender, perMint);

        IInscribeERC20(insAddr).inscribe(address(this), perMint);
        // 添加流动性
        IUniswapV2Router02(router).addLiquidity(
            insAddr,
            address(weth),
            perMint * 2 * 10 ** IInscribeERC20(insAddr).decimals(),
            (amount / 2) * 10 ** IInscribeERC20(insAddr).decimals(),
            0,
            0,
            address(this),
            block.timestamp
        );
        IERC20(weth).safeTransfer(
            address(this),
            (amount / 2) * 10 ** IInscribeERC20(insAddr).decimals()
        );
    }

    function getBalance(
        address insAddr,
        address user
    ) public returns (uint256) {
        return IInscribeERC20(insAddr).balanceOf(user);
    }

    /**
     * 兑换收益
     * @param insAddr 铭文地址
     * @param liquidity 流动性
     */
    function getReward(address insAddr, uint liquidity) public onlyOwner {
        IUniswapV2Router02(router).removeLiquidity(
            insAddr,
            weth,
            liquidity,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    receive() external payable {}
}
