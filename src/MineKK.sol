// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Test, console} from "forge-std/Test.sol";

interface IKK {
    function mint(address to, uint amount) external;
}

contract MineKK is Ownable {
    address public kkAddress;
    address public weth;
    uint public constant PERWARD = 10 ether; // 每个区块收益
    uint public constant ROTE = 1e4; // 每个区块收益
    using SafeERC20 for IERC20;
    uint public totalStake; // 总抵押量
    uint public currentStakeInterest; // 当前利率 初始值 = 0

    struct stakeEntity {
        uint256 stakeAmount;
        uint256 reward;
        uint256 stakeBlock;
        uint stakeInterest; // 上一次存款/赎回时的利率
    }
    mapping(address => stakeEntity) public stakeMap;

    constructor(address _weth) Ownable(msg.sender) {
        weth = _weth;
    }

    function setkkAddress(address _kkAddress) public onlyOwner {
        kkAddress = _kkAddress;
    }

    function stake(uint wethAmount) public {
        require(wethAmount > 0, "amount must be greater than 0");

        stakeEntity memory entity = stakeMap[msg.sender];
        // 更新收益
        uint earn = pendingEarn(entity,entity.stakeAmount);
        console.log("earn:", earn / 1 ether);
         // 更新总质押
        totalStake += wethAmount;
        changeInterest();
        // 更新质押信息
        updateEntity(entity, wethAmount, earn, true);

        IERC20(weth).safeTransferFrom(msg.sender, address(this), wethAmount);
    }

    function unStake(uint wethAmount, bool isAll) public {
        require(wethAmount > 0, "amount must be greater than 0");

        stakeEntity memory entity = stakeMap[msg.sender];
        require(
            entity.stakeAmount >= wethAmount,
            "amount must be less than or equal to stakeAmount"
        );
        uint unStakeAmount = isAll ? entity.stakeAmount : wethAmount;
        // 更新收益
        uint earn = pendingEarn(entity, unStakeAmount);
        console.log("earn:", earn / 1 ether);
        // 更新总质押
        totalStake -= wethAmount;
        // 更新总份数额
        changeInterest();
        
        // 更新质押信息
        updateEntity(entity, unStakeAmount, earn, false);

        IERC20(weth).safeTransfer(msg.sender, wethAmount);
    }

    function claimReward(address user, uint amount) public {
        require(amount > 0, "amount must bigger than zero");
        stakeEntity memory entity = stakeMap[user];
        require(entity.reward >= amount, "not enough reward");
        entity.reward -= amount;
        // 发放收益
        IKK(kkAddress).mint(user, amount/ ROTE);
        stakeMap[user] = entity;
    }

    function pendingEarn(
        stakeEntity memory entity,uint amount
    ) internal view returns (uint reward) {
        if (entity.stakeAmount == 0) return 0;
        uint blockNum = block.number;
        console.log("blockNum", blockNum);

        reward = currentStakeInterest == 1 * ROTE
            ? (blockNum - entity.stakeBlock) *
                ROTE *
                amount 
            : (blockNum - entity.stakeBlock) *
                ROTE *
                amount *
                (currentStakeInterest - entity.stakeInterest);
        console.log(
            "blockNum - entity.stakeBlock",
            blockNum - entity.stakeBlock
        );
        console.log("currentStakeInterest",currentStakeInterest);
        console.log("entity.stakeInterest",entity.stakeInterest);
        console.log(
            "currentStakeInterest - entity.stakeInterest",
            currentStakeInterest - entity.stakeInterest
        );
    }

    /**
     * 更新累计利率
     */
    function changeInterest() internal {
        if (totalStake == 0) {
            currentStakeInterest = 1 * ROTE;
            return;
        }
        // percharge = 当前收取的fee/ 总存款
        uint rate = (PERWARD * ROTE) / totalStake;
        console.log("rate", rate);
        // 计算当前的累积利率
        currentStakeInterest = currentStakeInterest + rate;
        console.log("currentStakeInterest", currentStakeInterest);
    }

    function updateEntity(
        stakeEntity memory entity,
        uint wethAmount,
        uint earn,
        bool isAdd
    ) internal {
        isAdd
            ? entity.stakeAmount += wethAmount
            : entity.stakeAmount -= wethAmount;
        entity.reward += earn;
        entity.stakeBlock = block.number;
        entity.stakeInterest = currentStakeInterest;
        stakeMap[msg.sender] = entity;
    }
}
