# QAMarketplace

QAMarketplace is a subproject of Xnect that provides a question-and-answer marketplace where users can ask and answer questions with financial incentives.

## Core Features

### 1. Paid Questions

- Users can pay to ask questions to any Twitter/LinkedIn user
- Question price must be ≥ the minimum price set by the answerer (default: 0.01 BNB)
- Support for premium questions (higher payments get priority visibility)

### 2. Paid Answers

- Answerers receive 90% reward if they respond within 5 days, otherwise 45% of the reward
- Answerers can customize their minimum question price
- Earnings are automatically sent to the linked wallet

### 3. Paid Viewing

- Public conversations can be viewed by others for 10% of the original question price
- Revenue sharing: 45% to the questioner, 45% to the answerer, 10% platform fee

## Revenue Rules

### For Questioners

- Receive 50% of viewing revenue (automatically transferred to the payment wallet)
- If a question expires without an answer, receive 45% refund of the question price (must claim using the original payment wallet)

### For Answerers

- Base income: 90% of answer reward if completed within 5 days, 45% if answered after 5 days
- Viewing share: 40% of the viewing revenue generated from public conversations

## Account Management

### Wallet Binding

- Answer earnings and viewing revenue are settled through the bound wallet
- For unbound users, earnings are stored in a temporary balance until a wallet is linked

### Balance Information

- Earnings for unregistered/unbound users are stored in a temporary balance
- Historical earnings are transferred to the wallet once binding is completed

## Time Rules (5-Day Cycle)

### Normal Process

- Question asked → Answer within 5 days → Revenue distribution

### Timeout Handling

- Questioner receives 45% refund of the question price
- Answerer can still respond but receives no direct reward (can still earn from viewing revenue if the conversation is public)

## Special Rights

### Free Follow-up Questions

- Each question includes 1 free follow-up opportunity
- Follow-up content in public conversations will also be public

## Smart Contract Development

### Installation

```shell
npm install
```

### Compile Contracts

```shell
npx hardhat compile
```
