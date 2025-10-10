// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title KipuBank - A simple vault bank with per-transaction withdrawal limits and a global capacity cap
/// @author Gaston Terminiello
/// @notice Allows users to deposit ETH into their personal vault and withdraw up to a per-transaction limit.
/// @dev Implements the checks-effects-interactions pattern, custom errors, events, and a simple reentrancy guard.
/// Follows Solidity best practices for security, readability, and efficiency as of 2025.
contract KipuBank {

    /*
        ERRORS
    */

    /// @notice Thrown when attempting a zero-value deposit.
    error ZeroDeposit();

    /// @notice Thrown when attempting a zero-value withdrawal.
    error ZeroWithdrawal();

    /// @notice Thrown when the deposit would exceed the bank's global capacity.
    /// @param attemptedAmount The amount the user tried to deposit.
    /// @param availableRemaining The remaining capacity available in the bank.
    error BankCapExceeded(uint256 attemptedAmount, uint256 availableRemaining);

    /// @notice Thrown when the withdrawal amount exceeds the per-transaction limit.
    /// @param attempted The amount the user tried to withdraw.
    /// @param limit The configured per-transaction withdrawal limit.
    error WithdrawAmountExceedsLimit(uint256 attempted, uint256 limit);

    /// @notice Thrown when the user has insufficient balance for the requested action.
    /// @param available The user's current balance.
    /// @param required The required amount for the action.
    error InsufficientBalance(uint256 available, uint256 required);

    /// @notice Thrown when an ETH transfer fails.
    /// @param to The recipient address.
    /// @param amount The amount being transferred.
    error TransferFailed(address to, uint256 amount);

    /// @notice Thrown when a reentrancy attempt is detected.
    error Reentrancy();

    /// @notice Thrown when the bank capacity is set to an invalid value (zero).
    error InvalidBankCap();

    /*
        EVENTS
    */

    /// @notice Emitted when a user deposits ETH into their vault.
    /// @param account The address of the user making the deposit.
    /// @param amount The amount of ETH deposited.
    /// @param newUserBalance The user's updated balance after the deposit.
    event Deposit(address indexed account, uint256 amount, uint256 newUserBalance);

    /// @notice Emitted when a user withdraws ETH from their vault.
    /// @param account The address of the user making the withdrawal.
    /// @param amount The amount of ETH withdrawn.
    /// @param newUserBalance The user's updated balance after the withdrawal.
    event Withdrawal(address indexed account, uint256 amount, uint256 newUserBalance);

    /*
        IMMUTABLES
    */

    /// @notice The global capacity limit for total ETH that can be deposited in the bank.
    uint256 public immutable bankCap;

    /// @notice The maximum amount that can be withdrawn in a single transaction.
    uint256 public immutable withdrawLimitPerTx;

    /*
        STORAGE
    */

    /// @notice Mapping of user addresses to their ETH balances in the bank.
    mapping(address => uint256) private userBalances;

    /// @notice Mapping of user addresses to the count of their deposit transactions.
    mapping(address => uint256) private userDepositCounts;

    /// @notice Mapping of user addresses to the count of their withdrawal transactions.
    mapping(address => uint256) private userWithdrawalCounts;

    /// @notice The total amount of ETH currently held in the bank (sum of all user balances).
    uint256 public totalBankFunds;

    /// @notice The global count of all deposit transactions across all users.
    uint256 public totalDepositTransactions;

    /// @notice The global count of all withdrawal transactions across all users.
    uint256 public totalWithdrawalTransactions;

    /*
        REENTRANCY GUARD
    */

    /// @dev Status flag for the reentrancy guard: 1 indicates not entered, 2 indicates entered.
    uint8 private reentrancyStatus;

    /// @dev Constant for reentrancy guard: indicates the function has not been entered.
    uint8 private constant NOT_ENTERED = 1;

    /// @dev Constant for reentrancy guard: indicates the function has been entered.
    uint8 private constant ENTERED = 2;

    /*
        CONSTRUCTOR
    */

    /// @notice Initializes the contract with the bank capacity and per-transaction withdrawal limit.
    /// @param _bankCap The global capacity limit for the bank (must be greater than zero).
    /// @param _withdrawLimitPerTx The maximum withdrawal amount per transaction (can be zero, but not recommended).
    constructor(uint256 _bankCap, uint256 _withdrawLimitPerTx) {
        if (_bankCap == 0) revert InvalidBankCap();
        bankCap = _bankCap;
        withdrawLimitPerTx = _withdrawLimitPerTx;

        reentrancyStatus = NOT_ENTERED;
    }

    /*
        MODIFIERS
    */

    /// @dev Prevents reentrancy attacks by locking the function during execution.
    modifier nonReentrant() {
        if (reentrancyStatus == ENTERED) revert Reentrancy();
        reentrancyStatus = ENTERED;
        _;
        reentrancyStatus = NOT_ENTERED;
    }

    /*
        PUBLIC FUNCTIONS
    */

    /// @notice Allows a user to deposit ETH into their personal vault.
    /// @dev Checks for zero value and cap exceedance before updating state. Emits a Deposit event.
    function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        uint256 newTotalFunds = totalBankFunds + msg.value;
        if (newTotalFunds > bankCap) {
            uint256 remainingCapacity = bankCap - totalBankFunds;
            revert BankCapExceeded(msg.value, remainingCapacity);
        }

        userBalances[msg.sender] += msg.value;
        totalBankFunds = newTotalFunds;
        userDepositCounts[msg.sender] += 1;
        totalDepositTransactions += 1;

        emit Deposit(msg.sender, msg.value, userBalances[msg.sender]);
    }

    /// @notice Allows a user to withdraw a specified amount of ETH from their vault.
    /// @param amount The amount of ETH to withdraw (must be greater than zero and within limits).
    /// @dev Follows checks-effects-interactions: validates inputs, updates state, then transfers ETH.
    /// Protected against reentrancy. Emits a Withdrawal event.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroWithdrawal();

        if (amount > withdrawLimitPerTx) revert WithdrawAmountExceedsLimit(amount, withdrawLimitPerTx);

        uint256 currentBalance = userBalances[msg.sender];
        if (amount > currentBalance) revert InsufficientBalance(currentBalance, amount);

        unchecked {
            userBalances[msg.sender] = currentBalance - amount;
        }
        totalBankFunds -= amount;
        userWithdrawalCounts[msg.sender] += 1;
        totalWithdrawalTransactions += 1;

        _safeTransferETH(msg.sender, amount);

        emit Withdrawal(msg.sender, amount, userBalances[msg.sender]);
    }

    /// @notice Retrieves the current ETH balance of a specified account.
    /// @param account The address of the account to query.
    /// @return The balance of the account in wei.
    function getBalance(address account) external view returns (uint256) {
        return userBalances[account];
    }

    /// @notice Retrieves statistics for a user's vault, including balance and transaction counts.
    /// @param account The address of the account to query.
    /// @return balance The current ETH balance of the user.
    /// @return depositCount The number of deposit transactions made by the user.
    /// @return withdrawalCount The number of withdrawal transactions made by the user.
    function getUserStats(address account) external view returns (uint256 balance, uint256 depositCount, uint256 withdrawalCount) {
        balance = userBalances[account];
        depositCount = userDepositCounts[account];
        withdrawalCount = userWithdrawalCounts[account];
    }

    /*
        PRIVATE HELPERS
    */

    /// @dev Safely transfers ETH to a recipient using a low-level call.
    /// @param to The recipient address.
    /// @param amount The amount of ETH to transfer.
    /// @return data The return data from the call (if any).
    function _safeTransferETH(address to, uint256 amount) private returns (bytes memory data) {
        (bool success, bytes memory returnData) = to.call{value: amount}("");
        if (!success) revert TransferFailed(to, amount);
        return returnData;
    }

    /*
        FALLBACK / RECEIVE
    */

    /// @notice Handles direct ETH transfers to the contract as deposits.
    /// @dev Mirrors the deposit() function logic for consistency.
    receive() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        uint256 newTotalFunds = totalBankFunds + msg.value;
        if (newTotalFunds > bankCap) {
            uint256 remainingCapacity = bankCap - totalBankFunds;
            revert BankCapExceeded(msg.value, remainingCapacity);
        }

        userBalances[msg.sender] += msg.value;
        totalBankFunds = newTotalFunds;
        userDepositCounts[msg.sender] += 1;
        totalDepositTransactions += 1;

        emit Deposit(msg.sender, msg.value, userBalances[msg.sender]);
    }

    /// @notice Reverts any non-standard calls to the contract.
    /// @dev Ensures only defined functions or receive() can be called.
    fallback() external payable {
        revert();
    }
}