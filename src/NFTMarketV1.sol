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
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title NftMarket，token购买，收手续费，质押eth获得token
 * 通过预言机获取到eth -> token的价格，
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

/**
 * @title 用eth购买nft，购买时需要支付gas费，支持staking ETH来赚取gas费
 * @author
 * @notice
 */
contract NFTMarket is Ownable, IERC721Receiver, EIP712, Nonces {
    IMyERC721 public nft;
    address public router;
    address public immutable token;
    address public immutable weth;
    using SafeERC20 for IERC20;
    mapping(uint => uint) public listPrice; //tokenId =>price
    mapping(uint => bool) public onSale;
    mapping(uint => address) public nftOwner; // tokenId => address
    address[] path;
    uint public feeRate; // 购买手续费率
    uint public totalFee; // 总共收取的手续费
    uint public totalStake; //总存款
    uint public constant DIVIEND = 1000;
    // uint public stakeRateOneBlock; // 一个区块的存款利率
    uint public accrualBlockNumber; // 上次计息快高
    uint public currentStakeInterest; // 当前利率

    struct stakeEntity {
        uint amount; // 存款金额
        uint reward; // 奖励金额
        uint claimAmount; // 已提取奖励
        uint stakeInterest; // 上一次存款/赎回时的利率
    }

    mapping(address => stakeEntity) public stakeMap; // 用户地址 => 质押数据
    mapping(address => bool) public isStake; // 用户地址 => 是否质押

    event listToken(address user, uint256 tokenId, uint256 price);
    event buy(address user, uint256 tokenId, uint256 amount, uint fee);
    event userStake(address user, uint256 amount);
    event userUnStake(address user, uint256 amount);
    event ClaimToken(address user, uint256 amount);
    event updateInterest(uint beforeInterest, uint afterInterest);

    error notOnSale();
    error hasBeBuyError();
    error priceError();
    error onSaled();

    constructor(
        address nftAddr,
        address _weth,
        address _token,
        address routerAddr
    ) Ownable(msg.sender) EIP712("NFTMarket", "1") {
        nft = IMyERC721(nftAddr);
        weth = _weth;
        token = _token;
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

    function stakingETH(uint wEthAmount) public payable {
        require(wEthAmount > 0, "amount must bigger than zero");

        stakeEntity memory entity = stakeMap[msg.sender];

        uint earn = computeEarn(entity);
        updateEntity(entity, wEthAmount, earn, true);
        // 质押
        IERC20(address(weth)).transferFrom(
            msg.sender,
            address(this),
            wEthAmount
        );
        totalStake += wEthAmount;
    }

    function unStakeETH(uint wEthAmount, bool isAll) public {
        require(isStake[msg.sender], "not stake");
        require(wEthAmount > 0, "amount must bigger than zero");
        uint stakeAmount = stakeMap[msg.sender].amount;
        require(wEthAmount <= stakeAmount, "amount error");
        uint unStakeAmount;
        stakeEntity memory entity = stakeMap[msg.sender];
        // 计算收益
        uint earn = computeEarn(entity);

        unStakeAmount = isAll ? entity.amount : wEthAmount;
        updateEntity(entity, unStakeAmount, earn, false);

        // 赎回本金
        IERC20(address(weth)).transferFrom(
            address(this),
            msg.sender,
            unStakeAmount
        );
        // 更新总质押量
        totalStake -= unStakeAmount;
    }

    function claimToken(address user, uint amount) public {
        require(amount > 0, "amount must bigger than zero");
        stakeEntity memory entity = stakeMap[user];
        require(entity.reward >= amount, "not enough reward");
        entity.reward -= amount;
        // 更新总fee
        totalFee -= amount;
        // 提取奖励
        IERC20(token).transferFrom(address(this), msg.sender, amount);
        stakeMap[user] = entity;

        emit ClaimToken(msg.sender, amount);
    }

    /**
     * 更新累计利率
     */
    function changeInterest(uint fee) internal {
        uint currentBlockNumber = block.number; //获取当前区块高度
        //如果上次计息时也在相同区块，则不重复计息。
        if (accrualBlockNumber == currentBlockNumber) {
            return;
        }
        // percharge = 当前收取的fee/ 总存款
        uint rate = fee / totalStake;
        // 计算当前的累积利率
        currentStakeInterest = currentStakeInterest + rate;

        // 更新计息时间
        accrualBlockNumber = currentBlockNumber;
    }

    function computeEarn(
        stakeEntity memory entity
    ) internal view returns (uint earn) {
        if (entity.amount == 0) {
            return 0;
        }
        earn = entity.amount * (currentStakeInterest - entity.stakeInterest);
    }

    function updateEntity(
        stakeEntity memory entity,
        uint ethAmount,
        uint earn,
        bool isAdd
    ) internal {
        // 增加收益
        entity.reward += earn;
        isAdd ? entity.amount += ethAmount : entity.amount -= ethAmount;
        entity.stakeInterest = currentStakeInterest;
        stakeMap[msg.sender] = entity;
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
    function buyNft(
        uint tokenId,
        uint amount,
        uint amountInMax,
        address coin
    ) public {
        if (!onSale[tokenId]) {
            revert notOnSale();
        }

        // 交手续费
        uint256 fee = (listPrice[tokenId] * feeRate) / DIVIEND;

        if (coin != address(token)) {
            console.log("exchange");
            // 交换代币到指定token,这里需要调用exchange的swap方法
            path.push(coin);
            path.push(token);

            // 买之前的token
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));

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

            // 买之后的token
            uint256 balanceAfter = IERC20(address(token)).balanceOf(
                address(this)
            );

            if (balanceAfter < balanceBefore + listPrice[tokenId] + fee) {
                revert priceError();
            }

            // 转给卖家的
            amount = balanceAfter - balanceBefore - fee;
        } else {
            if (amount - fee < listPrice[tokenId]) {
                revert priceError();
            }

            // 交手续费
            IERC20(address(token)).safeTransferFrom(
                msg.sender,
                address(this),
                fee
            );
        }
        console.log("fee:", fee);
        // 重新计算E
        changeInterest(fee);
        totalFee += fee;
        // token转给卖家的
        IERC20(address(token)).safeTransferFrom(
            msg.sender,
            nftOwner[tokenId],
            amount
        );

        nft.safeTransferFrom(address(this), msg.sender, tokenId);
        onSale[tokenId] = false;
        emit buy(msg.sender, tokenId, amount, fee);
    }
}
