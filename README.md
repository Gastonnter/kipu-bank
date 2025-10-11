# KipuBank Smart Contract

## Overview

KipuBank is a Solidity-based smart contract that implements a simple, secure vault banking system on the Ethereum blockchain. It enables users to deposit ETH into personal vaults and withdraw funds with built-in restrictions for enhanced security. The contract enforces a global capacity cap on total deposits to prevent overcommitment and a per-transaction withdrawal limit to mitigate risks from large or unauthorized transfers.

Designed with modern Solidity best practices (as of 2025), the contract prioritizes security, readability, and gas efficiency. It incorporates the **checks-effects-interactions (CEI)** pattern to avoid reentrancy vulnerabilities, **custom errors** for better error handling and reduced gas costs, **events** for on-chain logging, and a **non-reentrant modifier** for critical functions. The contract is suitable for decentralized applications (dApps) requiring controlled ETH storage, such as yield farming vaults, escrow services, or simple banking prototypes.

### Key Features

- **Personal Vaults**: Each user's balance is tracked independently via a mapping.
- **Deposit Mechanism**: Supports direct ETH transfers (via `receive()`) and explicit deposits, with checks for zero-value and capacity limits.
- **Withdrawal Mechanism**: Limited by a per-transaction cap, protected against reentrancy, and follows CEI for safe external interactions.
- **Statistics Tracking**: Maintains counts of deposits and withdrawals per user and globally.
- **Immutable Configurations**: Bank capacity and withdrawal limits are set at deployment and cannot be changed.
- **Error Handling**: Uses custom errors for precise, gas-efficient reverts.
- **Events**: Logs deposits and withdrawals for easy off-chain monitoring.

## Requirements

- **Solidity Version**: `^0.8.20` (uses features like custom errors and immutable variables).
- **Ethereum Compatibility**: Deployable on any EVM-compatible network (e.g., Ethereum Mainnet, Sepolia testnet, or layer-2 solutions like Optimism).
- **Development Tools**: Recommended tools include Hardhat, Foundry, or Remix IDE for compilation, testing, and deployment.
- **Dependencies**: None; the contract is self-contained.

## Deployment

Deployment requires specifying two immutable parameters in the constructor:

- `_bankCap`: The maximum total ETH (in wei) the bank can hold across all users. Must be greater than zero; otherwise, reverts with `InvalidBankCap`.
- `_withdrawLimitPerTx`: The maximum ETH (in wei) withdrawable in a single transaction. Can be zero (effectively disabling withdrawals), but not recommended for usability.

### Steps for Deployment

1. **Compile the Contract**:
   - Use a Solidity compiler compatible with version `0.8.20+`.
   - In **Remix**: Paste the code into a new file, select the compiler, and compile.

2. **Prepare Parameters**:
   - Convert values to wei (e.g., use `ethers.parseEther("1000")` for 1000 ETH as bank cap).

3. **Deploy Using Tools**:
   - **Remix IDE**:
     - Select **"Injected Provider - MetaMask"** for the environment.
     - Enter constructor arguments and click **"Deploy"**.
     - Confirm the transaction in MetaMask.

## Verification

On public networks, verify the source code on explorers like **Etherscan** using tools such as Hardhat's verify task or Remix's verification plugin.

## 📡 How to Interact with the Contract

You can interact with the contract using any of the following methods:

- **Wallets**: Connect via MetaMask or other Web3-compatible wallets.
- **JavaScript Libraries**: Use `ethers.js`, `web3.js`, or similar to script interactions.
- **Development Environments**: Deploy and test directly in [Remix IDE](https://remix.ethereum.org/).

> 💡 **Note**:  
> - **Mutable functions** (e.g., `deposit()`) **require gas** and modify the blockchain state.  
> - **View functions** (e.g., `getBalance()`) are **read-only and free** to call.

---

## ⚙️ Core Functions

### `deposit()`  
**Visibility**: `external`  
**Mutability**: `payable`

#### 🎯 Purpose
Deposits ETH into the caller’s personal vault within the contract.

#### ✅ Requirements
- `msg.value > 0` (must send a non-zero amount of ETH)
- Total contract funds after deposit **must not exceed** the `bankCap`

#### 🚫 Reverts If
- `ZeroDeposit`: `msg.value == 0`
- `BankCapExceeded`: Deposit would cause total funds to surpass `bankCap`

#### 🔄 Effects
- Increases the caller’s individual balance
- Updates the global `totalFunds` counter
- Increments the user’s deposit count
- Emits a `Deposit(address indexed user, uint256 amount)` event

---

### `withdraw(uint256 amount)`  
**Visibility**: `external`  
**Mutability**: `nonReentrant`

#### 🎯 Purpose
Withdraws a specified amount of ETH from the caller’s vault.

#### ✅ Requirements
- `amount > 0`
- `amount <= withdrawLimitPerTx`
- Caller has **sufficient balance** to cover the withdrawal

#### 🚫 Reverts If
- `ZeroWithdrawal`: `amount == 0`
- `WithdrawAmountExceedsLimit`: `amount > withdrawLimitPerTx`
- `InsufficientBalance`: User balance is less than `amount`
- `TransferFailed`: ETH transfer to the user fails (e.g., due to fallback limitations)
- `Reentrancy`: A reentrant call is detected (protected via OpenZeppelin’s `ReentrancyGuard`)

#### 🔄 Effects
- Decreases the caller’s individual balance
- Updates the global `totalFunds` counter
- Increments the user’s withdrawal count
- Transfers ETH to the caller
- Emits a `Withdrawal(address indexed user, uint256 amount)` event

---

## 👁️ View Functions

### `getBalance(address account)`  
**Visibility**: `external view`

#### 🎯 Purpose
Returns the ETH balance (in **wei**) for a given account stored in the contract.

#### 📥 Parameters
- `account` (`address`): The address whose balance you want to query.

#### 📤 Returns
- `uint256`: The user’s current balance in wei.

### `getUserStats(address account)`  
**Visibility**: `external view`

**Purpose**: Returns a tuple of `(balance, depositCount, withdrawalCount)` for the specified account.

- **`balance`**: The user’s current ETH balance in **wei**.  
- **`depositCount`**: Total number of successful deposits made by the user.  
- **`withdrawalCount`**: Total number of successful withdrawals made by the user.





---



