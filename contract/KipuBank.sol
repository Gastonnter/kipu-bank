// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title KipuBank - A simple vault bank with per-transaction withdrawal limits and a global capacity cap
/// @author Gaston Terminiello
/// @notice Allows users to deposit ETH into their personal vault and withdraw up to a per-transaction limit.
/// @dev Implements CEI pattern, custom errors, events, and reentrancy guard.
contract KipuBank {

    /*//////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Thrown when an invalid function call is made to the contract.
    error InvalidFunctionCall();

    /// @notice Thrown when the withdrawal limit is invalid (zero or exceeds cap).
    error WithdrawLimitExceedsCap();

    /// @notice Thrown when an invalid address (address(0)) is provided.
    error InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

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
    
    /// @notice Emitted when funds are reconciled to match actual contract balance.
    /// @param actualBalance The actual ETH balance of the contract.
    /// @param recordedBalance The internal accounting balance.
    event FundsReconciled(uint256 actualBalance, uint256 recordedBalance);

    /*//////////////////////////////////////////////////////////////
                          IMMUTABLES & CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The global capacity limit for total ETH that can be deposited in the bank.
    uint256 public immutable bankCap;

    /// @notice The maximum amount that can be withdrawn in a single transaction.
    uint256 public immutable withdrawLimitPerTx;

    // Reentrancy guard constants
    /// @dev Constant for reentrancy guard: indicates the function has not been entered.
    uint256 private constant NOT_ENTERED = 1;
    
    /// @dev Constant for reentrancy guard: indicates the function has been entered.
    uint256 private constant ENTERED = 2;
    
    // Security constants
    /// @dev Gas limit for external ETH transfers to prevent gas griefing attacks.
    uint256 private constant TRANSFER_GAS_LIMIT = 10000;

    /*//////////////////////////////////////////////////////////////
                          STORAGE VARIABLES
    //////////////////////////////////////////////////////////////*/

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

    /// @dev Status flag for the reentrancy guard: 1 indicates not entered, 2 indicates entered.
    uint256 private reentrancyStatus;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with the bank capacity and per-transaction withdrawal limit.
    /// @param _bankCap The global capacity limit for the bank (must be greater than zero).
    /// @param _withdrawLimitPerTx The maximum withdrawal amount per transaction (must be greater than zero and less than cap).
    constructor(uint256 _bankCap, uint256 _withdrawLimitPerTx) {
        if (_bankCap == 0) revert InvalidBankCap();
        if (_withdrawLimitPerTx == 0 || _withdrawLimitPerTx >= _bankCap) {
            revert WithdrawLimitExceedsCap();
        }
        bankCap = _bankCap;
        withdrawLimitPerTx = _withdrawLimitPerTx;
        reentrancyStatus = NOT_ENTERED;
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/


    /// @dev Prevents reentrancy attacks by locking the function during execution.
    modifier nonReentrant() {
        if (reentrancyStatus == ENTERED) revert Reentrancy();
        reentrancyStatus = ENTERED;
        _;
        reentrancyStatus = NOT_ENTERED;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows a user to deposit ETH into their personal vault.
    /// @dev Checks for zero value and cap exceedance before updating state. Emits a Deposit event.
     function deposit() external payable nonReentrant {
        _deposit();
    }

    /// @notice Allows a user to withdraw a specified amount of ETH from their vault.
    /// @param amount The amount of ETH to withdraw (must be greater than zero and within limits).
    /// @dev Follows checks-effects-interactions: validates inputs, updates state, then transfers ETH.
    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroWithdrawal();
        
        if (amount > withdrawLimitPerTx) {
            revert WithdrawAmountExceedsLimit(amount, withdrawLimitPerTx);
        }

        address sender = msg.sender;
        uint256 currentBalance = userBalances[sender];
        
        if (amount > currentBalance) revert InsufficientBalance(currentBalance, amount);
        
        unchecked {
            userBalances[sender] = currentBalance - amount;
            totalBankFunds -= amount;
            ++userWithdrawalCounts[sender];
            ++totalWithdrawalTransactions;
        }

        _safeTransferETH(sender, amount);

        emit Withdrawal(sender, amount, userBalances[sender]);
    }

    /// @notice Reconciles internal accounting with actual contract balance.
    /// @dev Can be called by anyone if there's a discrepancy (e.g., from selfdestruct).
    /// Only updates if actual balance is greater than recorded balance.
    function reconcileFunds() external {
        uint256 actualBalance = address(this).balance;
        uint256 recordedBalance = totalBankFunds;

        if (actualBalance > recordedBalance) {
            totalBankFunds = actualBalance;
            emit FundsReconciled(actualBalance, recordedBalance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves the current ETH balance of a specified account.
    /// @param account The address of the account to query.
    /// @return The balance of the account in wei.
    function getBalance(address account) external view returns (uint256) {
       if (account == address(0)) revert InvalidAddress();
       return userBalances[account];
    }

    /// @notice Retrieves statistics for a user's vault, including balance and transaction counts.
    /// @param account The address of the account to query.
    /// @return balance The current ETH balance of the user.
    /// @return depositCount The number of deposit transactions made by the user.
    /// @return withdrawalCount The number of withdrawal transactions made by the user.
    function getUserStats(address account)
     external
     view
     returns (
        uint256 balance, 
        uint256 depositCount,
        uint256 withdrawalCount
        ) 
    {
        if (account == address(0)) revert InvalidAddress();
        balance = userBalances[account];
        depositCount = userDepositCounts[account];
        withdrawalCount = userWithdrawalCounts[account];
    }

     /*//////////////////////////////////////////////////////////////
                        PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Safely transfers ETH to a recipient using a low-level call.
    /// @param to The recipient address.
    /// @param amount The amount of ETH to transfer.
    /// @notice Gas limit prevents griefing attacks from malicious receive() functions.
    function _safeTransferETH(address to, uint256 amount) private {
        if (to == address(0)) revert InvalidAddress();
        (bool success,) = to.call{value: amount, gas: TRANSFER_GAS_LIMIT}("");
        if (!success) revert TransferFailed(to, amount);
    }

    /// @dev Internal deposit logic used by both deposit() and receive().
    /// @notice Caller MUST apply nonReentrant modifier.
    function _deposit() private {
        uint256 amount = msg.value;

        if (amount == 0) revert ZeroDeposit();

        // Check capacity before accepting deposit
        uint256 newTotalFunds = totalBankFunds + amount;
        if (newTotalFunds > bankCap) {
            uint256 remainingCapacity = bankCap - totalBankFunds;
            revert BankCapExceeded(amount, remainingCapacity);
        }

        // Update user balance and total funds
        address sender = msg.sender;
        userBalances[sender] += amount;
        totalBankFunds = newTotalFunds;

        // Update transaction counters (safe from overflow in unchecked)
        unchecked {
            ++userDepositCounts[sender];
            ++totalDepositTransactions;
        }

        emit Deposit(sender, amount, userBalances[sender]);
    }

   /*//////////////////////////////////////////////////////////////
                        FALLBACK / RECEIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Handles direct ETH transfers to the contract as deposits.
    /// @dev Calls internal _deposit() function with reentrancy protection.
    receive() external payable nonReentrant {
       _deposit();
    }
    /// @notice Reverts any non-standard calls to the contract.
    /// @dev Ensures only defined functions or receive() can be called.
    fallback() external payable {
        revert InvalidFunctionCall();
    }
}
