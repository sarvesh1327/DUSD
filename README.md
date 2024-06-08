## Decentralized Stable Coin (DUSD)

It follows these Conditions
1. (Relative stability) Anchored or pegged--> $1.00
   1. Chainlink price feed
   2. Set a function to exchange ETH&BTC-->$$
2. Stability Mechanism-->Algorithmic(Decentralized)
   1. People can only mint stable coin with enough collatral(coded)
3. Collateral :Exogenous(crypto)
   1. wETH
   2. wBTC
   
Contracts:
DUSD.sol:
    The ERC20 implementation of Stable coin(DUSD)
DUSDEngine.sol:
    This is the contract which controls the DUSD contract and maintain the collateral for it.

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
