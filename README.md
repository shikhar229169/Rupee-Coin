# Rupee-Coin
A Decentralized Stable coin pegged with Indian Rupee, allows user to deposit collateral and mint Rupee Coin.

It is a relative stable coin which is pegged with Indian Rupee
It allows people to deposit collateral, and borrow the Rupee Coin, which is a Decentralized Stable Coin pegged with Indian Rupee. User can withdraw their collateral deposted, they can burn the coin in case their health factor gets broken. Also allows users to liquidate the defaulters, and get rewarded.
It uses algorithmic approach to facilitate everything.
User can deposit collateral in the ERC20 version of ETH and BTC, which is wrapped ETH (wETH) and wrapped BTC (wBTC). Thus the collateral type is Exogeneous.

## Our Contracts
Rupee Coin - https://sepolia.etherscan.io/address/0x0C177D19b02559c46A10E138Ce27BF87eE874577

Rupee Coin Engine - https://sepolia.etherscan.io/address/0xCE1A2cc91c7Fc49017bE01A6CbcCCb9FcEb441fa

## To get the price feeds for eth and btc, it is achieved via chainlink functions:
EthToInrPriceFeed - https://sepolia.etherscan.io/address/0x38c6D12DC5aee7A804e5Ce4CFef47a0a684C829d#code

BtcToInrPriceFeed - https://sepolia.etherscan.io/address/0xf5600144B2A0c9b02812A6daE790dA1129c4b7df#code

## To deposit collateral as eth to get Rupee Coin:
- User needs to deposit eth in the wETH contract - https://sepolia.etherscan.io/address/0xdd13E55209Fd76AfE204dBda4007C227904f0a81#writeContract
- Then user needs to approve the Rupee Coin Engine Contract on the WETH contract with the required amount of eth to be deposited in Rupee Coin Engine.
- After that user can call the depositCollateral function on the Rupee Coin Engine and can mint Rupee Coin within the threshold amount so that health factor is always greater than required for the protocol.
