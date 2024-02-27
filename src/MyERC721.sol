// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Nonces.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Test, console} from "forge-std/Test.sol";

contract MyERC721 is Ownable,ERC721URIStorage,Nonces,EIP712{
    Nonces  tokenIds;
    bytes32 private constant _BUYBYSIG_TYPEHASH = keccak256("BuyBySig(uint256 tokenId,uint256 price)");

    constructor () ERC721("MyErc721", "MY721")Ownable(msg.sender)EIP712("MyERC721","1"){
    }

    function mint(address to) public onlyOwner{
        uint256 tokenId = nonces(address(this));
        _mint(to, tokenId);
        _useNonce(address(this));
    }
    
    function setTokenURI(uint256 tokenId, string memory _tokenURI) public  {
        _setTokenURI(tokenId, _tokenURI);
    }

    /**
     * 当前的tokenId
     */
    function currentTokenId() public view returns(uint){
        return nonces(address(this)) -1;
    }

    function getNftBalance(address user) public view returns(uint256){
        return balanceOf(user);
    }

    /**
     * 离线签名全部授权
     * @param tokenId tokenId
     * @param price price
     * @param v v
     * @param r r
     * @param s s
     */
    function offlineApprove(address to,uint256 tokenId, uint256 price, uint8 v, bytes32 r, bytes32 s) public returns(bool){
        // TO: 
        bytes32 structHash = keccak256(abi.encode(_BUYBYSIG_TYPEHASH, tokenId,price));

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(hash, v, r, s);
        console.log("signer::::",signer);
        require(_ownerOf(tokenId) == signer, "BuyBySig: invalid signature");
        // 给nftMarket全部授权
        _setApprovalForAll(signer, to, true);
        return true;
    }



}