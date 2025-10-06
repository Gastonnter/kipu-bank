// SPDX-License-Identifier: MIT
pragma solidity >0.8.20;

/// @title KipuBank - Simple vault bank with per-tx withdrawal limit and global cap
/// @ author - Gaston Terminiello
/// @notice Permite a los usuarios depositar ETH en su bóveda personal y retirar hasta un límite por transacción.
/// @dev Implementa checks-effects-interactions, errores personalizados, eventos y un simple reentrancy guard.
contract KipuBank {
    
    /*
        ERRORS
    */

    error ZeroDeposit();
    error BankCapExceeded(uint256 attemptedAmount, uint256 availableRemaining );
    error WithdrawAmountExceedsLimit(uint256 attempted, uint256 limit);
    error InsufficientBalance(uint256 available, uint256 required);
    error TransferFailed(address to, uint256 amount);
    error Reentrancy();

    /*
        EVENTS
    */

    event Deposit(address indexed account, uint256 amount, uint256 totalBalance);
    event Withdrawal(address indexed account, uint256 amount, uint256 totalBalance);


    /*
        IMMUTABLE
    */

    uint256 public immutable bankCap;
    uint256 public immutable withdrawLimitPerTx;

    /*
        STORAGE
    */

    mapping(address => uint256) private balances;
    mapping(address => uint256) private depositsCount;
    mapping(address => uint256) private withdrawalsCount;
    uint256 public totalDeposited;
    uint256 public totalDeposits;
    uint256 public totalWithdrawals;

    /*
        REENTRACY GUARD
    */

    uint8 private _status;
    uint8 private constant _NOT_ENTERED = 1;
    uint8 private constant _ENTERED = 2;

    /*
        CONSTRUCTOR
    */

       constructor(uint256 _bankCap, uint256 _withdrawLimitPerTx) {
        require(_bankCap > 0, "bankCap>0");
        bankCap = _bankCap;
        withdrawLimitPerTx = _withdrawLimitPerTx;

        _status = _NOT_ENTERED;
    }

    /*
        MODIFIERS
    */

       modifier nonReentrant() {
        if (_status == _ENTERED) revert Reentrancy();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /*
        PUBLIC FUNCTIONS
    */

     function deposit() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        uint256 newTotal = totalDeposited + msg.value;
        if (newTotal > bankCap) {
            uint256 remaining = bankCap - totalDeposited;
            revert BankCapExceeded(msg.value, remaining);
        }

        balances[msg.sender] += msg.value;
        totalDeposited = newTotal;
        depositsCount[msg.sender] += 1;
        totalDeposits += 1;

        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert InsufficientBalance(balances[msg.sender], 0);

        if (amount > withdrawLimitPerTx) revert WithdrawAmountExceedsLimit(amount, withdrawLimitPerTx);

        uint256 userBalance = balances[msg.sender];
        if (amount > userBalance) revert InsufficientBalance(userBalance, amount);

        unchecked {
            balances[msg.sender] = userBalance - amount;
        }
        totalDeposited -= amount;
        withdrawalsCount[msg.sender] += 1;
        totalWithdrawals += 1;

        // Interaction: transfer ETH
        _safeTransferETH(msg.sender, amount);

        emit Withdrawal(msg.sender, amount, balances[msg.sender]);
    }


    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    function getUserStats(address account) external view returns (uint256 balance, uint256 depositCount, uint256 withdrawalCount) {
        balance = balances[account];
        depositCount = depositsCount[account];
        withdrawalCount = withdrawalsCount[account];
    }

    /*
        PRIVATE HELPERS
    */

    function _safeTransferETH(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed(to, amount);
    }

    /*
        FALLBACK / RECEIVE
    */

     receive() external payable {
        if (msg.value == 0) revert ZeroDeposit();

        uint256 newTotal = totalDeposited + msg.value;
        if (newTotal > bankCap) {
            uint256 remaining = bankCap - totalDeposited;
            revert BankCapExceeded(msg.value, remaining);
        }

        balances[msg.sender] += msg.value;
        totalDeposited = newTotal;
        depositsCount[msg.sender] += 1;
        totalDeposits += 1;

        emit Deposit(msg.sender, msg.value, balances[msg.sender]);
    }

    fallback() external payable {
        revert();
    }

}   