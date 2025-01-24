// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/token/ERC1155/ERC1155.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/utils/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/utils/Strings.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/utils/Address.sol";

contract NFTCollection is ERC1155, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    string public constant contractName = "420";
    string public collectionName;
    string public collectionURI;

    struct MintData {
        uint256 mintID;
        address[] tokenAddresses;
        mapping(address => bool) hasToken;
    }

    uint256 public constant MAX_MINT_PER_WALLET = 3;
    uint256 public constant VESTING_PERIOD = 90 days;
    uint256 public constant VESTING_INTERVAL = 30 days;
    uint256 public constant VESTING_PERCENTAGE = 10;

    bool public mintActive;
    uint256 public mintPrice = 0.1 ether;
    uint256 public maxMintSupply = 1000;
    
    uint256 public currentMintID;
    uint256 public currentMintSupply;
    
    mapping(address => uint256) public allocatedContractTokens;
    mapping(address => uint256) public userMintedCount;
    mapping(uint256 => MintData) public mintTokens;
    mapping(uint256 => mapping(address => uint256)) public mintTokenInitialBalance;
    mapping(uint256 => mapping(address => uint256)) public mintTokenWithdrawn;
    mapping(uint256 => mapping(address => uint256)) public mintTokenVestDate;

    event TokensDeposited(uint256 indexed mintID, address indexed token, uint256 amount);
    event MintCreated(address indexed recipient, uint256 mintID);
    event TokensWithdrawn(address indexed user, uint256 mintID, address token, uint256 amount);
    event CollectionURIUpdated(string newURI);
    event MintStateChanged(bool active);
    event ETHCleared(uint256 amount);
    event ERC20Cleared(address token, uint256 amount);

    constructor(
        string memory _collectionName,
        string memory _collectionURI
    ) ERC1155(_collectionURI) Ownable(msg.sender) {
        collectionName = _collectionName;
        collectionURI = _collectionURI;
    }

    modifier validMint(uint256 mintID) {
        require(mintID <= currentMintID && mintID > 0, "Invalid mint ID");
        _;
    }

    function clearETH() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to clear");
        payable(owner()).sendValue(balance);
        emit ETHCleared(balance);
    }

    function clearERC20(address token) external onlyOwner nonReentrant {
        uint256 availableBalance = IERC20(token).balanceOf(address(this)) - allocatedContractTokens[token];
        require(availableBalance > 0, "No available tokens");
        IERC20(token).safeTransfer(owner(), availableBalance);
        emit ERC20Cleared(token, availableBalance);
    }

    function setMintActive(bool active) external onlyOwner {
        mintActive = active;
        emit MintStateChanged(active);
    }

    function setCollectionURI(string memory newURI) external onlyOwner {
        collectionURI = newURI;
        emit CollectionURIUpdated(newURI);
    }

    function setCollectionName(string memory newName) external onlyOwner {
        collectionName = newName;
    }

    function depositTokens(uint256 mintID, address token, uint256 amount) external onlyOwner {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Invalid amount");
        
        MintData storage data = mintTokens[mintID];
        if (!data.hasToken[token]) {
            data.tokenAddresses.push(token);
            data.hasToken[token] = true;
            mintTokenVestDate[mintID][token] = block.timestamp + VESTING_PERIOD;
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        mintTokenInitialBalance[mintID][token] += amount;
        allocatedContractTokens[token] += amount;

        emit TokensDeposited(mintID, token, amount);
    }

    function adminMint(address recipient, uint256 quantity) external onlyOwner {
        require(recipient != address(0), "Invalid recipient");
        require(quantity <= 50 && quantity > 0, "Invalid quantity");
        require(currentMintSupply + quantity <= maxMintSupply, "Exceeds max supply");

        for (uint256 i = 0; i < quantity; i++) {
            _mint(recipient, ++currentMintID, 1, "");
            currentMintSupply++;
            emit MintCreated(recipient, currentMintID);
        }
    }

    function mint() external payable nonReentrant {
        require(mintActive, "Minting inactive");
        require(msg.value >= mintPrice, "Insufficient ETH");
        require(currentMintSupply < maxMintSupply, "Max supply reached");
        require(userMintedCount[msg.sender] < MAX_MINT_PER_WALLET, "Max 3 mints per wallet");

        _mint(msg.sender, ++currentMintID, 1, "");
        currentMintSupply++;
        userMintedCount[msg.sender]++;

        emit MintCreated(msg.sender, currentMintID);

        if (msg.value > mintPrice) {
            payable(msg.sender).sendValue(msg.value - mintPrice);
        }
    }

    function burn(uint256 mintID) external validMint(mintID) {
        require(balanceOf(msg.sender, mintID) == 1, "Not owner");

        MintData storage data = mintTokens[mintID];
        for (uint256 i = 0; i < data.tokenAddresses.length; i++) {
            address token = data.tokenAddresses[i];
            uint256 remaining = mintTokenInitialBalance[mintID][token] - mintTokenWithdrawn[mintID][token];
            allocatedContractTokens[token] -= remaining;
            delete mintTokenInitialBalance[mintID][token];
            delete mintTokenWithdrawn[mintID][token];
            delete mintTokenVestDate[mintID][token];
        }
        
        delete mintTokens[mintID];
        _burn(msg.sender, mintID, 1);
        currentMintSupply--;
    }

    function withdraw(uint256 mintID) external validMint(mintID) nonReentrant {
        require(balanceOf(msg.sender, mintID) == 1, "Not owner");

        MintData storage data = mintTokens[mintID];
        for (uint256 i = 0; i < data.tokenAddresses.length; i++) {
            address token = data.tokenAddresses[i];
            _processWithdrawal(mintID, token);
        }
    }

    function uri(uint256) public view override returns (string memory) {
        return collectionURI;
    }

    function getMintTokens(uint256 mintID) external view returns (address[] memory) {
        return mintTokens[mintID].tokenAddresses;
    }

    function _processWithdrawal(uint256 mintID, address token) private {
        require(block.timestamp >= mintTokenVestDate[mintID][token], "Vesting not started");
        
        uint256 timePassed = block.timestamp - mintTokenVestDate[mintID][token];
        uint256 intervals = timePassed / VESTING_INTERVAL;
        intervals = intervals > 10 ? 10 : intervals;

        uint256 totalWithdrawable = (mintTokenInitialBalance[mintID][token] * VESTING_PERCENTAGE * intervals) / 100;
        uint256 available = totalWithdrawable - mintTokenWithdrawn[mintID][token];

        if (available > 0) {
            mintTokenWithdrawn[mintID][token] += available;
            allocatedContractTokens[token] -= available;
            IERC20(token).safeTransfer(msg.sender, available);
            emit TokensWithdrawn(msg.sender, mintID, token, available);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155) returns (bool) {
    return super.supportsInterface(interfaceId);
    }
}
