// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import "../src/interfaces/IUniswapV2Router02.sol";
import "./WETH9.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title NftMarket，实现上线、购买nft、拥有白名单购买、离线上线
 */
interface IMyERC721 {
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(uint256 tokenId) external view returns (address);

    function ownerOf(uint256 tokenId) external view returns (address);
}

contract NFTMarket is Ownable, IERC721Receiver, EIP712, Nonces {
    IMyERC721 public nft;
    // IERC20 public token;
    address public router;
    WETH9 public weth;
    using SafeERC20 for IERC20;
    mapping(uint => uint) public listPrice; //tokenId =>price
    mapping(uint => bool) public onSale;
    mapping(uint => address) public nftOwner; // tokenId => address
    address[] path;

    error notOnSale();
    error hasBeBuyError();
    error priceError();
    error onSaled();
    event listToken(address user, uint256 tokenId, uint256 price);
    event buy(address user, uint256 tokenId, uint256 amount);

    constructor(
        address nftAddr,
        WETH9 _weth,
        address routerAddr
    ) Ownable(msg.sender) EIP712("NFTMarket", "1") {
        nft = IMyERC721(nftAddr);
        weth = _weth;
        router = routerAddr;
    }

    modifier checkPrice(uint price) {
        require(price > 0, "price must bigger than zero");
        _;
    }

    /**
     * 如果合约想接受nft必须实现该方法
     */
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * nft上架
     */
    function list(uint tokenId, uint price) public checkPrice(price) {
        if (onSale[tokenId]) {
            revert onSaled();
        }
        nft.safeTransferFrom(msg.sender, address(this), tokenId);
        nft.approve(msg.sender, tokenId);
        listPrice[tokenId] = price;
        nftOwner[tokenId] = msg.sender;
        onSale[tokenId] = true;
        emit listToken(msg.sender, tokenId, price);
    }
    


    /**
     * 购买nft
     * @param tokenId tokenid
     * @param amount 价格
     */
    function buyNft(uint tokenId, uint amount, address coin) public {
        if (!onSale[tokenId]) {
            revert notOnSale();
        }
        if (coin != address(weth)) {
            console.log("exchange");
            // 交换代币到指定token,这里需要调用exchange的swap方法
            path.push(coin);
            path.push(address(weth));

            uint256 balanceBefore = IERC20(address(weth)).balanceOf(address(this));

            // coin先转给market
            IERC20(coin).safeTransferFrom(msg.sender, address(this), amount);
            // market 授权给router
            IERC20(coin).approve(
                address(router),
                IERC20(coin).balanceOf(address(this))
            );
            // 调用router的swap方法
            IUniswapV2Router02(router)
                .swapExactTokensForTokens(
                    amount,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );

            uint256 balanceAfter = IERC20(address(weth)).balanceOf(address(this));

            if (balanceAfter < balanceBefore + listPrice[tokenId]) {
                revert priceError();
            }
        } else {
            if (amount < listPrice[tokenId]) {
                revert priceError();
            }
            IERC20(address(weth)).safeTransferFrom(msg.sender, address(this), amount);
        }

        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        onSale[tokenId] = false;
        emit buy(msg.sender, tokenId, amount);
    }
}