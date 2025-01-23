// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/token/ERC1155/ERC1155.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/utils/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.2/contracts/utils/Strings.sol";

contract ERC420 is ERC1155, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct mintToken_data {
        uint256 mintID;
        address[] tokenAddress;
    }

    bool public mintActive;

    mapping(address => uint256) public allocatedContractTokens;
    
    uint256 public currentMintID;
    string public mintURI = "ipfs://bafkreifpc6oda3eqfq6plborptqkn5sfewx7xky44blziiwzy4nubx7vfe/";

    uint256 public mintPrice = .1 * (10 ** 18);
    uint256 public maxMintSupply = 1000;
    uint256 public currentMintSupply;

    bool public sharedURI;

    mapping(uint256 => mintToken_data) public mintTokens;
    mapping(uint256 => mapping(address => uint256)) public mintTokenBalance;
    mapping(uint256 => mapping(address => uint256)) public mintTokenVestDate;
    mapping(uint256 => mapping(address => uint256)) public mintTokenLastWithdraw;

    uint256 public constant vestingPeriod = 90 days;
    uint256 public constant vestingInterval = 30 days;
    uint256 public constant vestingWithdrawPct = 10;

    event adminAction(string Action, address Address, uint256 Amount);
    event userAction(string actionTaken_, address actionAddress, uint256 actionValue_, bool actionResult_);

    constructor() Ownable(msg.sender) ERC1155(mintURI) {}

    /*
     * Admin functions
     */

    // Clear WETH from contract
    function clearWETH() external onlyOwner nonReentrant {
        uint256 fullBalance = address(this).balance;
        (bool sendSuccess, ) = payable(owner()).call{value: fullBalance}("");

        if (sendSuccess) {
            emit adminAction("clearWETH", address(0), fullBalance);
        } else {
            emit adminAction("clearWETH", address(0), 0);
        }
    }

    // Remove full balance of given token
    function clearE20Token(address token_) external onlyOwner nonReentrant {
        uint256 availableBalance = IERC20(token_).balanceOf(address(this)) - allocatedContractTokens[token_];
        require(availableBalance > 0, "No available tokens");

        IERC20(token_).safeTransfer(owner(), availableBalance);

        emit adminAction("clearE20Token", token_, availableBalance);
    }

    // Enable or disable new minting
    function setMintActive(bool mintActive_) external onlyOwner {
        mintActive = mintActive_;

        emit adminAction("setMintActive", msg.sender, mintActive_ ? 0 : 1 );
    }

    // Enable or disable unique URI JSON
    function setSharedURI(bool sharedURI_) external onlyOwner {
        sharedURI = sharedURI_;

        emit adminAction("setSharedURI", msg.sender, sharedURI_ ? 0 : 1 );
    }

    // Deposit tokens to a specific mint
    // TOKEN APPROVAL MUST HAPPEN EXTERNALLY FIRST
    function depositTokens(uint256 mintID_, address tokenAddress_, uint256 tokenAmount_) external onlyOwner {
        mintTokens[mintID_].mintID = mintID_;

        bool newToken = true;
        for (uint256 ct; ct < mintTokens[mintID_].tokenAddress.length; ct++) {
            if (mintTokens[mintID_].tokenAddress[ct] == tokenAddress_) {
                newToken = false;
                break;
            }
        }

        if (newToken) {
            mintTokens[mintID_].tokenAddress.push(tokenAddress_);
            mintTokenVestDate[mintID_][tokenAddress_] = block.timestamp + vestingPeriod;
        }

        IERC20(tokenAddress_).safeTransferFrom(msg.sender, address(this), tokenAmount_);
        mintTokenBalance[mintID_][tokenAddress_] += tokenAmount_;
        allocatedContractTokens[tokenAddress_] += tokenAmount_;

        emit adminAction("depositTokens", tokenAddress_, tokenAmount_);
    }

    // Allow contract owner to mint to a specific address
    function newMintToUser(address mintRecipient_, uint256 mintQTY_) external onlyOwner {
        require(mintRecipient_ != address(0), "Cannot mint to 0 address");
        require(mintQTY_ <= 50, "Max mint batch is 50");
        require(currentMintSupply + mintQTY_ <= maxMintSupply, "Quantity would exceed max supply");

        for (uint256 bMint; bMint < mintQTY_; bMint++) {
            uint256 adminMintID = doMint(mintRecipient_);

            emit adminAction("newMintToUser", mintRecipient_, adminMintID);
        }
    }

    /*
     * User Functions
     */
    
    // Mint NFT
    function newMint() external payable nonReentrant {
        if (msg.sender != owner()) {
            require(msg.value >= mintPrice, "Not enough ETH");
        }

        uint256 userMintID = doMint(msg.sender);

        emit userAction("newMint", msg.sender, userMintID, true);
    }

    // Burn NFT
    function burnMint(uint256 mintID_) external {
        require(balanceOf(msg.sender, mintID_) > 0, "Nothing to burn");

        for (uint256 ct; ct < mintTokens[mintID_].tokenAddress.length; ct++) {
            address curToken = mintTokens[mintID_].tokenAddress[ct];
            allocatedContractTokens[curToken] -= mintTokenBalance[mintID_][curToken];
            mintTokenBalance[mintID_][curToken] = 0;
        }

        delete mintTokens[mintID_];

        _burn(msg.sender, mintID_, 1);

        currentMintSupply--;

        emit userAction("burnMint", msg.sender, mintID_, true);
    }

    // Withdraw tokens from a mint
    function withdrawTokensFromMint(uint256 mintID_) external {
        require(balanceOf(msg.sender, mintID_) > 0, "Sender does not own this mint");

        for (uint256 ct; ct < mintTokens[mintID_].tokenAddress.length; ct++) {
            address curToken = mintTokens[mintID_].tokenAddress[ct];
            if (
                block.timestamp >= mintTokenVestDate[mintID_][curToken] &&
                block.timestamp >= mintTokenLastWithdraw[mintID_][curToken] + vestingInterval
            ) {
                uint256 withdrawAmount = (mintTokenBalance[mintID_][curToken] * vestingWithdrawPct) / 100;
                IERC20(curToken).safeTransfer(msg.sender, withdrawAmount);
                mintTokenBalance[mintID_][curToken] -= withdrawAmount;
                allocatedContractTokens[curToken] -= withdrawAmount;
                mintTokenLastWithdraw[mintID_][curToken] = block.timestamp;

                emit userAction("withdrawTokensFromMint1", msg.sender, mintID_, true);
                emit userAction("withdrawTokensFromMint2", curToken, withdrawAmount, true);
            } else {
                emit userAction("withdrawTokensFromMint1", msg.sender, mintID_, false);
                emit userAction("withdrawTokensFromMint2", curToken, 0, false);
            }
        }
    }

    /*
     * Support Functions
     */
    
    // Perform mint actions
    function doMint(address mintRecipient_) internal returns (uint256) {
        require(currentMintSupply < maxMintSupply, "Cannot mint any more NFTs");
        require(mintActive || msg.sender == owner(), "Minting is currently unavailable");

        uint256 newMintID = ++currentMintID;
        _mint(mintRecipient_, newMintID, 1, "");
        
        currentMintSupply++;

        return newMintID;
    }
    
    // Return URI as string
    function uri(uint256 mintID_) override public view returns (string memory) {
        if (sharedURI) {
            return string(abi.encodePacked(mintURI, "metadata.json"));
        } else {
            return string(abi.encodePacked(mintURI, Strings.toString(mintID_),".json"));
        }
    }

    // List all tokens associated with a mint
    function showMintTokens(uint256 mintID_) external view returns (address[] memory) {
        return mintTokens[mintID_].tokenAddress;
    }

    // KDR-20250115
}
