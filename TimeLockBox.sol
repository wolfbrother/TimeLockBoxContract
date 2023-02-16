//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

//import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//import "@openzeppelin/contracts/utils/Strings.sol";

contract TimeLockBox {
    address public owner;
    uint128 public counter;
    mapping(address => bool) private legalErc20Tokens;
    mapping(address => Receipt) private receiptRepo;
    mapping(address => bool) private hasReceipt;
    struct Receipt {
        address customer;
        // address(0) in this contract means Ether
        address token;
        uint256 amount;
        uint256 unlockTime;
        bool isEther;
    }

    using SafeERC20 for IERC20;

    event Deposit(
        address receiptKey,
        address customer,
        address token,
        uint256 amount,
        uint256 lockDays,
        uint256 unlockTime
    );
    event Withdraw(
        address receiptKey,
        address customer,
        address token,
        uint256 amount,
        uint256 time
    );
    event NewOwner(address oldOwner, address newOwner);
    event AddToken(address token);

    constructor() {
        owner = msg.sender;
        counter = 0;
    }

    function _computeReceiptKey(Receipt memory _receipt, uint256 _counter)
        private
        view
        returns (address)
    {
        return
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encode(
                                _receipt.customer,
                                _counter + block.timestamp
                            )
                        )
                    )
                )
            );
    }

    modifier _isLegalErc20Token(address _token) {
        require(legalErc20Tokens[_token], "not legal token");
        _;
    }

    modifier _notContractAddress(address _address) {
        require(!Address.isContract(_address), "not support contract address");
        _;
    }

    modifier _isLegalLockdays(uint256 _lockDays) {
        require(
            (_lockDays > 0) && (_lockDays <= 3650),
            "lockDays is too large or small"
        );
        _;
    }

    function _getUnlockTime(uint256 _lockDays) private view returns (uint256) {
        return _lockDays * 86400 + block.timestamp;
    }

    function _incrementCounter() private {
        unchecked {
            counter = counter + 1;
        }
    }

    function addToken(address _token) public {
        require(msg.sender == owner, "only owner can add tokens");
        legalErc20Tokens[_token] = true;
        emit AddToken(_token);
    }

    function changeOwner(address _newOwner) public {
        require(msg.sender == owner, "only owner can add tokens");
        owner = _newOwner;
        emit NewOwner(msg.sender, owner);
    }

    function getReceipt(address _receiptKey) public {
        require(hasReceipt[_receiptKey], "has not receipt or already drawn");
        Receipt memory receipt = receiptRepo[_receiptKey];
        emit Deposit(
            _receiptKey,
            receipt.customer,
            receipt.token,
            receipt.amount,
            0,
            receipt.unlockTime
        );
    }

    function depositEther(uint256 _lockDays)
        public
        payable
        _notContractAddress(msg.sender)
        _isLegalLockdays(_lockDays)
    {
        require(msg.value > 0, "ether amount <= 0");
        _incrementCounter();
        uint256 unlockTime = _getUnlockTime(_lockDays);
        Receipt memory receipt = Receipt(
            msg.sender,
            address(0),
            msg.value,
            unlockTime,
            true
        );
        address receiptKey = _computeReceiptKey(receipt, counter);
        require(!hasReceipt[receiptKey], "receipt key collision");
        receiptRepo[receiptKey] = receipt;
        hasReceipt[receiptKey] = true;

        emit Deposit(
            receiptKey,
            msg.sender,
            address(0),
            msg.value,
            _lockDays,
            unlockTime
        );
    }

    function depositErc20Token(
        address _token,
        uint256 _amount,
        uint256 _lockDays
    )
        public
        _isLegalErc20Token(_token)
        _notContractAddress(msg.sender)
        _isLegalLockdays(_lockDays)
    {
        require(_amount > 0, "token amount <= 0");
        _incrementCounter();

        uint256 unlockTime = _getUnlockTime(_lockDays);
        Receipt memory receipt = Receipt(
            msg.sender,
            _token,
            _amount,
            unlockTime,
            false
        );
        address receiptKey = _computeReceiptKey(receipt, counter);
        require(!hasReceipt[receiptKey], "receipt key collision");
        receiptRepo[receiptKey] = receipt;
        hasReceipt[receiptKey] = true;
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(
            receiptKey,
            msg.sender,
            _token,
            _amount,
            _lockDays,
            unlockTime
        );
    }

    function withdraw(address _receiptKey) public {
        require(hasReceipt[_receiptKey], "no valid receipt");
        require(
            receiptRepo[_receiptKey].unlockTime < block.timestamp,
            "unlock time not reached"
        );
        hasReceipt[_receiptKey] = false;
        Receipt memory receipt = receiptRepo[_receiptKey];

        if (receipt.isEther) {
            payable(receipt.customer).transfer(receipt.amount);
        } else {
            IERC20(receipt.token).safeTransfer(
                receipt.customer,
                receipt.amount
            );
        }
        emit Withdraw(
            _receiptKey,
            receipt.customer,
            receipt.token,
            receipt.amount,
            block.timestamp
        );
    }
}
