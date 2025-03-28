// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract QAMarketplace is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bool public paused;
    uint8 public questionFee;
    uint8 public refundFee;
    uint8 public viewFee;

    uint8 public askerRefundPercentage;
    uint8 public answererRefundPercentage;

    uint8 public viewRewardPercentage;
    uint8 public askerViewRewardPercentage;
    uint8 public answererViewRewardPercentage;

    uint256 public MIN_REWARD;

    address public server;

    struct QASession {
        uint256 id;
        string askerId;
        string answererId;
        string questionContent;
        uint256 reward;
        address paymentAddress;
        bool resolved;
        bool terminated;
        uint256 creationTimestamp;
        uint256 expiryTimestamp;
    }

    // store the mapping relationship between address and twitterId
    mapping(address => string) public addressToUid;
    mapping(string => address) public uidToAddress;

    // record if the address is registered
    mapping(address => bool) public registeredAddresses;
    mapping(string => bool) public registeredUIds;

    // if the answerer is answered, the reward will be stored in the mapping
    mapping(string => uint256) public answererEarnings;
    mapping(string => uint256) public pendingRewards;

    // store the questions
    mapping(uint256 => QASession) public questions;

    event Registered(string indexed uid, address indexed user);
    event QuestionSubmitted(
        uint256 indexed questionId,
        string askerId,
        string answererId,
        address paymentAddress,
        uint256 reward,
        uint256 expiryTimestamp
    );
    event QuestionProcessed(
        uint256 indexed questionId,
        string askerId,
        string answererId,
        uint256 rewardToAnswerer,
        uint256 fee
    );
    event QuestionExpired(
        uint256 indexed questionId,
        string askerId,
        string answererId,
        uint256 refundToAsker,
        uint256 rewardToAnswerer,
        uint256 fee
    );
    event QuestionViewed(
        uint256 indexed questionId,
        string viewerId,
        string askerId,
        string answererId,
        uint256 rewardToAsker,
        uint256 rewardToAnswerer,
        uint256 fee
    );

    event AskerRewarded(string indexed askerId, address to, uint256 reward);

    event AnswererRewarded(
        string indexed answererId,
        address to,
        uint256 reward
    );

    modifier onlyServer() {
        require(msg.sender == server, "You are not the server");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    function initialize(address _server) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        server = _server;
        paused = false;
        _setDefaultParameters();
    }

    function _setDefaultParameters() private {
        questionFee = 10;
        refundFee = 10;
        viewFee = 10;
        askerRefundPercentage = 45;
        answererRefundPercentage = 45;
        viewRewardPercentage = 10;
        askerViewRewardPercentage = 45;
        answererViewRewardPercentage = 45;
        MIN_REWARD = 0.01 ether;
    }

    function register(
        string calldata uid,
        address user,
        uint256 expirationTime,
        bytes calldata signature
    ) external whenNotPaused {
        // check if the address is already registered
        require(!registeredAddresses[user], "Address Already Used");
        require(!registeredUIds[uid], "UID Already Used");

        // check if the expierTime is greater than current timestamp
        require(
            expirationTime > block.timestamp,
            "ExpirationTime must be greater than current timestamp"
        );

        // get the eth signed message hash
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            abi.encode(uid, user, expirationTime)
        );
        // recover the signer address from the signature
        address signer = ECDSA.recover(ethSignedMessageHash, signature);

        // check if the signer is the authorized server address
        require(signer == server, "Invalid Signature");

        // // check if the user is the same as the msg.sender
        // require(user == msg.sender, "Address is not valid");

        // store the mapping relationship
        addressToUid[user] = uid;
        uidToAddress[uid] = user;
        registeredAddresses[user] = true;
        registeredUIds[uid] = true;

        // claim the reward if there is any
        uint256 reward = pendingRewards[uid];
        if (reward > 0) {
            pendingRewards[uid] = 0;
            _rewardAnswerer(uid, reward);
            emit AnswererRewarded(uid, user, reward);
        }

        emit Registered(uid, user);
    }

    function submitQuestion(
        uint256 _questionId,
        string calldata _askerId,
        string calldata _answererId,
        string calldata _questionContent,
        uint256 _minReward,
        uint256 _expiryTimestamp,
        bytes calldata _signature
    ) external payable whenNotPaused {
        require(
            msg.value >= MIN_REWARD,
            "Reward must be greater than MIN_REWARD"
        );
        require(
            _expiryTimestamp > block.timestamp,
            "ExpirationTime must be greater than current timestamp"
        );
        require(
            bytes(_questionContent).length <= 2000,
            "Question must be greater than 0 and less than 2000 characters"
        );

        // check if the signature is valid
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(
            abi.encode(
                _questionId,
                _askerId,
                _answererId,
                _questionContent,
                _minReward,
                _expiryTimestamp
            )
        );
        address signer = ECDSA.recover(ethSignedMessageHash, _signature);
        require(signer == server, "Invalid Signature");

        // check if the reward is greater than the minAnswerReward
        require(
            msg.value >= _minReward,
            "Reward must be greater than minReward"
        );

        QASession memory q = QASession({
            id: _questionId,
            askerId: _askerId,
            answererId: _answererId,
            questionContent: _questionContent,
            reward: msg.value,
            paymentAddress: msg.sender,
            resolved: false,
            terminated: false,
            creationTimestamp: block.timestamp,
            expiryTimestamp: _expiryTimestamp
        });
        questions[_questionId] = q;

        emit QuestionSubmitted(
            _questionId,
            _askerId,
            _answererId,
            msg.sender,
            msg.value,
            _expiryTimestamp
        );
    }

    function processQuestions(
        uint256[] calldata _questionIds,
        uint256[] calldata _answerTimestamps
    ) external onlyServer whenNotPaused {
        require(
            _questionIds.length == _answerTimestamps.length,
            "QuestionIds and AnswerTimestamps must have the same length"
        );

        for (uint256 i = 0; i < _questionIds.length; i++) {
            uint256 questionId = _questionIds[i];
            uint256 answerTimestamp = _answerTimestamps[i];

            QASession storage q = questions[questionId];
            require(q.paymentAddress != address(0), "Question does not exist");
            require(!q.resolved, "Question is already answered");
            require(!q.terminated, "Question is already canceled");

            if (q.expiryTimestamp <= answerTimestamp) {
                processExpiredQuestion(questionId); // cancelled reward sharing logic
                continue;
            }

            q.resolved = true;
            uint256 answerReward = (q.reward * (100 - questionFee)) / 100; // 90% to answerer
            uint256 fee = q.reward - answerReward; // 10% fee
            _rewardAnswerer(q.answererId, answerReward); // reward the answerer
            emit QuestionProcessed(
                questionId,
                q.askerId,
                q.answererId,
                answerReward,
                fee
            );
        }
    }

    function processExpiredQuestion(uint256 _questionId) public whenNotPaused {
        QASession storage q = questions[_questionId];
        require(!q.resolved, "Question is answered");
        require(!q.terminated, "Question is already canceled");
        require(
            q.expiryTimestamp <= block.timestamp,
            "Question is not expired"
        );

        q.terminated = true;
        uint256 fee = (q.reward * refundFee) / 100; // 10% fee
        uint256 refundValue = (q.reward * askerRefundPercentage) / 100; // 45% to asker
        uint256 rewardToAnswerer = q.reward - fee - refundValue; // 45% to answerer

        _rewardAnswerer(q.answererId, rewardToAnswerer);
        _rewardAsker(q.askerId, q.paymentAddress, refundValue);

        emit QuestionExpired(
            _questionId,
            q.askerId,
            q.answererId,
            refundValue,
            rewardToAnswerer,
            fee
        );
    }

    function viewQuestion(
        uint256 _questionId,
        string calldata _viewerId
    ) external payable whenNotPaused nonReentrant {
        QASession memory q = questions[_questionId];
        require(q.paymentAddress != address(0), "Question does not exist");
        require(q.resolved || q.terminated, "Question is not processed");
        uint256 reward = (q.reward * viewRewardPercentage) / 100;
        require(msg.value >= reward, "Value must be greater than viewReward");

        uint256 fee = (msg.value * viewFee) / 100; // 10% fee
        uint256 rewardToAsker = (msg.value * askerViewRewardPercentage) / 100; // 50% to asker
        uint256 rewardToAnswerer = msg.value - rewardToAsker - fee; // 40% to answerer

        _rewardAnswerer(q.answererId, rewardToAnswerer);
        _rewardAsker(q.askerId, q.paymentAddress, rewardToAsker);

        emit QuestionViewed(
            _questionId,
            _viewerId,
            q.askerId,
            q.answererId,
            rewardToAsker,
            rewardToAnswerer,
            fee
        );
    }

    function withdraw(address to) external onlyOwner {
        _safeTransfer(to, address(this).balance);
    }

    function _rewardAnswerer(string memory _uid, uint256 _reward) internal {
        answererEarnings[_uid] += _reward;
        address answererAddress = uidToAddress[_uid];
        if (answererAddress != address(0)) {
            _safeTransfer(answererAddress, _reward);
        } else {
            pendingRewards[_uid] += _reward;
        }
        emit AnswererRewarded(_uid, answererAddress, _reward);
    }

    function _rewardAsker(
        string memory _askerId,
        address _askerAddress,
        uint256 _reward
    ) internal {
        _safeTransfer(_askerAddress, _reward);
        emit AskerRewarded(_askerId, _askerAddress, _reward);
    }

    function _safeTransfer(address to, uint256 amount) private {
        require(to != address(0), "Invalid address");
        (bool success, ) = payable(to).call{value: amount}("");
        require(success, "Transfer failed");
    }

    function setMinReward(uint256 _minReward) external onlyOwner {
        MIN_REWARD = _minReward;
    }

    function setQuestionFee(uint8 _questionFee) external onlyOwner {
        questionFee = _questionFee;
    }

    function setRefundFee(uint8 _refundFee) external onlyOwner {
        refundFee = _refundFee;
    }

    function setServer(address _server) external onlyOwner {
        server = _server;
    }

    function setViewFee(uint8 _viewFee) external onlyOwner {
        viewFee = _viewFee;
    }

    function setAskerRefundPercentage(
        uint8 _askerRefundPercentage
    ) external onlyOwner {
        askerRefundPercentage = _askerRefundPercentage;
    }

    function setAnswererRefundPercentage(
        uint8 _answererRefundPercentage
    ) external onlyOwner {
        answererRefundPercentage = _answererRefundPercentage;
    }

    function setViewRewardPercentage(
        uint8 _viewRewardPercentage
    ) external onlyOwner {
        viewRewardPercentage = _viewRewardPercentage;
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function setAskerViewRewardPercentage(
        uint8 _askerViewRewardPercentage
    ) external onlyOwner {
        askerViewRewardPercentage = _askerViewRewardPercentage;
    }

    function setAnswererViewRewardPercentage(
        uint8 _answererViewRewardPercentage
    ) external onlyOwner {
        answererViewRewardPercentage = _answererViewRewardPercentage;
    }
}
