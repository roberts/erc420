# ERC-420

This is the official repository for the Drew Roberts Digital Standard of the ERC-420. Much like the ERC-404, this is neither an ERC nor would it be number 420 if it was. It's not intended to be a standard by the Ethereum Foundadion to Reqest Comments.

This smart contract is based on the ERC-1155 (NFT) standard & allows the NFT to accept an unlimited quantity and type of ERC-20 tokens. It contains the OpenZeppelin smart contract vesting features with a 90 day cliff period from when the token is received & a 10% withdrawal per month of those tokens.

The concept is that the NFTs in this collection will hold an additional secondary value close to the total value of the tokens included in the NFT, especially if they are stablecoin or wrapped BTC or other pegged tokens. The intention of the projects that use this standard is to use locked or burned liquidity pool structures on utility or memecoins allowing for long-term project involvement of the participants holding the NFTs.

In that regard the conceptual mental model for this contract is a trust fund or forced savings account that is truly decentralized & can be sold on secondary NFT exchanges or passed to pseudonoymous wallets on the blockchain.

## Functions

There are a number of funtions in the contract that can be adjusted. The main funstions are:

- Mint Price (0.1 ETH)
- Collection Size (1k default)
- Vesting Cliff (90 days)
- Withrawal amount (10%)
- Waiting period between withdrawals (30 days)

You can then view the full details of the contract & other terms in the 420.sol document in this repository.

## OpenZeppelin Contract Imports

- token/ERC1155/ERC1155.sol
- access/Ownable.sol
- token/ERC20/utils/SafeERC20.sol
- utils/ReentrancyGuard.sol
- utils/Strings.sol
