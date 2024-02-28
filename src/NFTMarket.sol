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
// import "./CETH.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
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

interface ICETH {
    function mint(address to, uint amount) external;
    function burn(address account, uint amount) external;
}

/**
 * @title 用eth购买nft，购买时需要支付gas费，支持staking ETH来赚取gas费
 * @author
 * @notice
 */
contract NFTMarket is Ownable, IERC721Receiver, EIP712, Nonces {
    IMyERC721 public nft;
    address public router;
    WETH9 public weth;
    address immutable public ceth;
    using SafeERC20 for IERC20;
    mapping(uint => uint) public listPrice; //tokenId =>price
    mapping(uint => bool) public onSale;
    mapping(uint => address) public nftOwner; // tokenId => address
    address[] path;
    uint public feeRate; // 购买手续费
    uint public totalFee; //总共收取的手续费
    uint public totalStake; //总存款  
    uint public constant DIVIEND = 1000;
    uint public stakeRateOneBlock; // 一个区块的存款利率
    uint public accrualBlockNumber; // 上次计息快高
    uint public currentStakeInterest; // 当前累积利率

    struct stakeEntity {
        address user; // 用户地址
        uint amount; // 质押的ETH数量
        uint stakeInterest; // 上一次存款/赎回时的累积利率
        uint stakingBlockNumber; // 质押快高
        uint lastUpdateBlockNumber; // 最后更新快高
    }
    
    mapping(address => stakeEntity) stakeMap; // 用户地址 => 质押数据
    mapping(address => bool) public isStake; // 用户地址 => 是否质押

    error notOnSale();
    error hasBeBuyError();
    error priceError();
    error onSaled();
    event listToken(address user, uint256 tokenId, uint256 price);
    event buy(address user, uint256 tokenId, uint256 amount);

    constructor(
        address nftAddr,
        WETH9 _weth,
        address _ceth,
        address routerAddr
    ) Ownable(msg.sender) EIP712("NFTMarket", "1") {
        nft = IMyERC721(nftAddr);
        weth = _weth;
        ceth = _ceth;
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

    function setBuyRateOneBlock(uint _rate) public onlyOwner {
        require(_rate < DIVIEND, "fee rate must less than 1000");
        require(0 < _rate, "fee rate must bigger than 0");

        stakeRateOneBlock = _rate;
    }

    function stakingETH(uint wEthAmount) payable public{
        require(wEthAmount > 0, "amount must bigger than zero");
        // 重新算累积利率
        accrueInterest();
        if (isStake[msg.sender]){
            // 质押过
            stakeEntity memory entity = stakeMap[msg.sender];
            // 本金*当前利率/存款时利率
            uint prinAndInt = entity.amount * currentStakeInterest / entity.stakeInterest ;
            entity.stakeInterest = currentStakeInterest;
            entity.amount = prinAndInt + wEthAmount;
            entity.lastUpdateBlockNumber = block.number;
            stakeMap[msg.sender] = entity;


        }else{
            // 没有质押过
            stakeMap[msg.sender] = stakeEntity(msg.sender, wEthAmount, currentStakeInterest, block.number, block.timestamp);
            isStake[msg.sender] = true;
        } 
        // 质押
        IERC20(address(weth)).transferFrom(msg.sender, address(this), wEthAmount);
        // 铸造cToken
        ICETH(ceth).mint(msg.sender, wEthAmount);

    }

    function unStakeETH(uint cEthAmount,bool isAll) public {
        require(isStake[msg.sender], "not stake");
        require(cEthAmount > 0, "amount must bigger than zero");
        require(cEthAmount <= IERC20(ceth).balanceOf(msg.sender), "amount error");
        uint unStakeAmount;
        // 重新算累积利率
        accrueInterest();
     
        stakeEntity memory entity = stakeMap[msg.sender];
        // 本金*当前利率/存款时利率
        uint prinAndInt = entity.amount * currentStakeInterest / entity.stakeInterest;
        entity.stakeInterest = currentStakeInterest;
        entity.lastUpdateBlockNumber = block.number;
        if (isAll) {
            isStake[msg.sender] = false;
            delete stakeMap[msg.sender];
            unStakeAmount = prinAndInt;
        }else{
            unStakeAmount = cEthAmount;
            entity.amount = prinAndInt - cEthAmount;
            stakeMap[msg.sender] = entity;
        }
         // 赎回 本金
            IERC20(address(weth)).transferFrom(address(this), msg.sender, unStakeAmount);
            // 销毁cToken
            ICETH(ceth).burn(msg.sender, cEthAmount);
        
    }

    /**
     * 更新累计利率
     */
    function accrueInterest() internal {
        uint currentBlockNumber = block.number; //获取当前区块高度
        //如果上次计息时也在相同区块，则不重复计息。
        if (accrualBlockNumber == currentBlockNumber) {
            return;
        }
        // 计算从上次计息到当前时刻的区间利率
        uint stakeRate = stakeRateOneBlock *
            (currentBlockNumber - accrualBlockNumber);
        // 更新总存款，总存款=总存款+利息=总存款+总存款*利率=总存款*（1+利率）
        totalStake = totalStake * (1 + stakeRate);
        // 更新累积利率：  最新borrowIndex= 上一个borrowIndex*（1+borrowRate）
        currentStakeInterest = currentStakeInterest * (1 + stakeRate);
        // 更新计息时间
        accrualBlockNumber = currentBlockNumber;
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
     * 购买nft 购买时需要判断利率是否更改
     * @param tokenId tokenid
     * @param amount 价格
     */
    function buyNft(uint tokenId, uint amount, uint amountInMax, address coin) public {
        if (!onSale[tokenId]) {
            revert notOnSale();
        }
        if (coin != address(weth)) {
            console.log("exchange");
            // 交换代币到指定token,这里需要调用exchange的swap方法
            path.push(coin);
            path.push(address(weth));

            // 买之前的weth
            uint256 balanceBefore = IERC20(address(weth)).balanceOf(
                address(this)
            );

            // coin先转给market
            IERC20(coin).safeTransferFrom(msg.sender, address(this), amount);
            // market 授权给router
            IERC20(coin).approve(
                address(router),
                IERC20(coin).balanceOf(address(this))
            );
            // 调用router的swap方法
            IUniswapV2Router02(router).swapTokensForExactTokens(
                amount,
                amountInMax,
                path,
                address(this),
                block.timestamp
            );

            // 交手续费
            uint256 fee = (listPrice[tokenId] * feeRate) / DIVIEND;
            IERC20(address(weth)).safeTransfer(address(this), fee);

            // 买之后的weth
            uint256 balanceAfter = IERC20(address(weth)).balanceOf(
                address(this)
            );

            if (balanceAfter < balanceBefore + listPrice[tokenId]) {
                revert priceError();
            }
        } else {
            uint256 balanceBefore = IERC20(address(weth)).balanceOf(
                address(this)
            );
            // 交手续费

            if (amount < listPrice[tokenId]) {
                revert priceError();
            }
            IERC20(address(weth)).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        onSale[tokenId] = false;
        emit buy(msg.sender, tokenId, amount);
    }
}
