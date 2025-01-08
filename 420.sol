// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC420 is ERC1155 {
    uint256 public currentTokenId;

    // Mapping to track the maximum supply of each token ID
    mapping(uint256 => uint256) public maxSupply;

    // Mapping to track the total minted supply of each token ID
    mapping(uint256 => uint256) public mintedSupply;

    // Mapping to track vesting start times for each token ID
    mapping(uint256 => uint256) public vestingStart;

    // Mapping to track the last withdrawal time for each token ID
    mapping(uint256 => uint256) public lastWithdrawalTime;

    // Vesting and withdrawal constants
    uint256 public constant VESTING_PERIOD = 90 days;
    uint256 public constant WITHDRAWAL_INTERVAL = 30 days;
    uint256 public constant WITHDRAWAL_PERCENTAGE = 10;

    // constructor(string memory uri) ERC1155(uri) {}
    constructor(string memory uri) ERC1155("ipfs://bafkreifpc6oda3eqfq6plborptqkn5sfewx7xky44blziiwzy4nubx7vfe") {}


    /**
     * @dev Create a new token type
     * @param _initialSupply The initial supply of tokens to mint
     * @param _maxSupply The maximum supply for the token type
     * @param _data Data to be passed if recipient is a contract
     */
    function createToken(uint256 _initialSupply, uint256 _maxSupply, bytes memory _data) external {
        require(_maxSupply > 0, "Max supply must be greater than zero");
        require(_initialSupply <= _maxSupply, "Initial supply cannot exceed max supply");

        uint256 tokenId = ++currentTokenId;
        maxSupply[tokenId] = _maxSupply;
        mintedSupply[tokenId] = _initialSupply;
        vestingStart[tokenId] = block.timestamp;

        if (_initialSupply > 0) {
            _mint(msg.sender, tokenId, _initialSupply, _data);
        }
    }

    /**
     * @dev Mint additional tokens of an existing type
     * @param _tokenId The token ID to mint
     * @param _amount The amount of tokens to mint
     * @param _data Data to be passed if recipient is a contract
     */
    function mint(uint256 _tokenId, uint256 _amount, bytes memory _data) external {
        require(maxSupply[_tokenId] > 0, "Token ID does not exist");
        require(mintedSupply[_tokenId] + _amount <= maxSupply[_tokenId], "Minting would exceed max supply");

        mintedSupply[_tokenId] += _amount;
        _mint(msg.sender, _tokenId, _amount, _data);
    }

    /**
     * @dev Burn tokens of a specific type
     * @param _tokenId The token ID to burn
     * @param _amount The amount of tokens to burn
     */
    function burn(uint256 _tokenId, uint256 _amount) external {
        require(balanceOf(msg.sender, _tokenId) >= _amount, "Insufficient balance to burn");
        _burn(msg.sender, _tokenId, _amount);
        mintedSupply[_tokenId] -= _amount;
    }

    /**
     * @dev Withdraw 10% of all ERC-20 tokens held by the contract for a specific token ID.
     * @param _tokenAddress The address of the ERC-20 token to withdraw.
     * @param _tokenId The ID of the ERC-1155 token to use for withdrawal logic.
     */
    function withdrawERC20(address _tokenAddress, uint256 _tokenId) external {
        require(balanceOf(msg.sender, _tokenId) > 0, "Caller does not own this token ID");
        require(vestingStart[_tokenId] + VESTING_PERIOD <= block.timestamp, "Vesting period not yet completed");
        require(lastWithdrawalTime[_tokenId] + WITHDRAWAL_INTERVAL <= block.timestamp, "Withdrawal interval not yet elapsed");

        IERC20 token = IERC20(_tokenAddress);
        uint256 contractBalance = token.balanceOf(address(this));
        uint256 withdrawalAmount = (contractBalance * WITHDRAWAL_PERCENTAGE) / 100;

        require(withdrawalAmount > 0, "No tokens available for withdrawal");

        lastWithdrawalTime[_tokenId] = block.timestamp;
        token.transfer(msg.sender, withdrawalAmount);
    }
}
