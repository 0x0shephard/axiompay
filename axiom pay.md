# **Project Proposal: AxiomPay**

## **The Stateful Settlement Protocol for the Autonomous Agent Economy**

### **1\. Executive Summary**

The digital economy is shifting from human-driven transactions to autonomous, agent-driven interactions. AI agents are moving from simple tools to economic actors that must discover, negotiate, and pay for services in real-time. This machine-to-machine (M2M) economy requires a new financial infrastructure—one that is programmatic, trust-minimized, and operates at the speed of software.

The current payment landscape is inadequate. Traditional APIs (e.g., Stripe) are slow, expensive, and require human-centric identity. New request-based protocols (like Coinbase's x402) are excellent for single, stateless transactions (a "toll booth") but are capital-inefficient for continuous, high-frequency services (like streaming data or renting compute).

**AxiomPay is the stateful settlement protocol for the agent economy.**

It is a custom-built, on-chain protocol that functions as a "utility meter," enabling one agent to pay another in real-time for *ongoing* services. By utilizing a novel, time-based escrow contract, AxiomPay allows a service provider to verifiably confirm that 100% of a session's funds are locked upfront. The provider can then "pull" payment on a per-second basis as the service is rendered, while the payer can cancel at any moment and be refunded for all unspent time.

This model combines the upfront trust of an escrow with the pay-as-you-go flexibility of streaming. Built on a low-cost L2 blockchain (like **Base**) and leveraging **ERC-4337 Account Abstraction** for agent identity, AxiomPay provides the critical, missing infrastructure for high-value agent interactions, positioning itself as the stateful settlement rail for emerging standards like Google's Agent Payments Protocol (AP2).

### **2\. The Problem: A Bottleneck in the Agent Economy**

The autonomous agent economy is projected to be a multi-trillion dollar industry, but it faces a fundamental bottleneck: **payments**.

1. **High Friction:** Traditional payments (credit cards, ACH) are built for humans. They are slow (T+2 settlement), expensive (2.9% \+ $0.30 fees), and require identity (KYC) and pre-established contracts. They are unusable for two agents that discover each other and need to transact for 30 seconds.  
2. **Stateless Micropayments (x402):** Protocols like x402 (HTTP 402\) are a massive leap forward, enabling per-request payments. However, this "toll booth" model is highly inefficient for continuous services. Renting a GPU for one hour would require 3,600 individual on-chain transactions, one for every second of compute. This is operationally infeasible and expensive.  
3. **Capital Inefficiency & Risk:** Existing streaming protocols (like Superfluid) are capital-efficient for the payer but introduce risk for the provider, who has no guarantee the payer's wallet will remain funded for the whole session.  
4. **Lack of a "Trust Primitive":** How does a service provider (e.g., a data agent) trust that a new, unknown agent (a consumer) will pay for a 60-minute data stream? How does the consumer trust they won't be charged if the service stops?

### **3\. The Solution: AxiomPay Protocol**

AxiomPay solves this by introducing a **Provider-Verifiable Escrow** model. It provides the trust of a traditional escrow with the granularity of a micropayment stream.

The core of our solution is AxiomStream.sol, a custom-built smart contract that manages time-locked payment agreements.

**The core interaction is simple:**

1. **Payer Agent** (e.g., WriterAgent) wants to rent 30 minutes of service from a **Provider Agent** (e.g., SummarizerAgent) at a rate of 0.001 USDC/second.  
2. **Fund:** The Payer Agent locks the *total session cost* (0.001 \* 1800 sec \= 1.8 USDC) into the AxiomStream contract.  
3. **Verify:** The Provider Agent instantly verifies on-chain that 1.8 USDC is locked for its benefit. Trust is established.  
4. **Stream:** The Provider Agent begins streaming the service (e.g., via an API). For every second that passes, 0.001 USDC becomes "earned" and is withdrawable by the Provider.  
5. **Cancel:** The Payer Agent can stop the service at any time (e.g., after 10 minutes). The AxiomStream contract instantly refunds the unearned, unused portion (20 minutes' worth) back to the Payer Agent, while the Provider is guaranteed its pay for the 10 minutes of service provided.

This model is the best of both worlds: the Provider has zero counterparty risk, and the Payer retains full control and flexibility.

### **4\. Technical Architecture**

AxiomPay is a 4-layer protocol designed for security, efficiency, and interoperability.

| Layer | Component | Technology | Purpose |
| :---- | :---- | :---- | :---- |
| **Layer 3: Agent Interaction** | **AxiomPay SDK** (Python/JS) | Your Custom SDK | A developer-friendly SDK that abstracts all on-chain complexity, allowing agents to startSession(), endSession(), and verifySession(). |
| **Layer 2: Protocol Contracts** | AxiomStream.sol ServiceRegistry.sol | Custom Solidity | AxiomStream.sol (The Core Protocol): Manages the time-based escrow, withdrawals, and refunds. ServiceRegistry.sol: An on-chain "Yellow Pages" for provider agents to register their services and prices. |
| **Layer 1: Settlement & Identity** | ERC-4337 Wallets Base L2 ERC-20 (USDC) | Account Abstraction Optimistic Rollup Stablecoin | ERC-4337: The de facto standard for agent identity. Gives each agent a "smart wallet" for automation, gas abstraction, and security (e.g., session keys). Base: The L2 of choice, providing sub-cent fees, fast settlement, and deep integration with the x402/Coinbase ecosystem. USDC: The stable asset for settlement. |
| **Layer 0: Execution** | **Ethereum** | Consensus & Security | The ultimate security and settlement layer for the Base L2. |

### **5\. Core Protocol Design: AxiomStream.sol**

This is the heart of AxiomPay. It is a new smart contract, optimized for this specific use case.

#### **5.1. The Stream Struct**

This is the data structure that defines each payment session.

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AxiomStream {

    struct Stream {  
        address payer;          // The agent paying for the service.  
        address provider;       // The agent providing the service.  
        IERC20 token;           // The ERC-20 token being streamed (e.g., USDC).  
        uint256 ratePerSecond;  // The amount of tokens earned per second.  
        uint256 startTime;      // The block.timestamp when the stream began.  
        uint256 duration;       // The total number of seconds funded.  
        uint256 totalAmount;    // The total amount locked in escrow.  
        uint256 withdrawnAmount;// Total tokens already pulled by the provider.  
    }

    // Mapping from a unique streamId to the Stream struct  
    mapping(uint256 \=\> Stream) public streams;  
    uint256 public nextStreamId;

    // Events for off-chain monitoring  
    event StreamStarted(uint256 indexed streamId, address indexed payer, address indexed provider, uint256 totalAmount, uint256 ratePerSecond);  
    event StreamWithdrawn(uint256 indexed streamId, uint256 amount);  
    event StreamStopped(uint256 indexed streamId, address indexed payer, uint256 providerRefund, uint256 payerRefund);  
}

#### **5.2. Core Functions**

**1\. startStream(address provider, IERC20 token, uint256 ratePerSecond, uint256 duration)**

* **Action:** Called by the Payer Agent to initiate and fund a session.  
* **Logic:**  
  1. Calculates totalAmount \= ratePerSecond \* duration.  
  2. Pulls the totalAmount of the token from the Payer Agent (which must have given prior ERC-20 approve).  
  3. Creates and stores a new Stream struct.  
  4. Sets startTime \= block.timestamp.  
  5. Emits StreamStarted.

**2\. withdrawFromStream(uint256 streamId)**

* **Action:** Called by the Provider Agent to pull their earned funds.  
* **Logic:**  
  1. Calculates elapsedTime \= block.timestamp \- stream.startTime (capped at duration).  
  2. Calculates totalEarned \= elapsedTime \* stream.ratePerSecond.  
  3. Calculates availableToWithdraw \= totalEarned \- stream.withdrawnAmount.  
  4. Transfers availableToWithdraw to the stream.provider.  
  5. Updates stream.withdrawnAmount \+= availableToWithdraw.  
  6. Emits StreamWithdrawn.

**3\. stopStream(uint256 streamId)**

* **Action:** Called by the Payer Agent to terminate the session early.  
* **Logic:**  
  1. First, calls a private function \_payOutProvider(streamId) to pay the provider for all time elapsed up to this exact second.  
  2. Calculates remainingBalance \= stream.totalAmount \- stream.withdrawnAmount.  
  3. Transfers the remainingBalance (the un-earned, unused funds) back to the stream.payer.  
  4. Deletes the stream from storage to save gas.  
  5. Emits StreamStopped.

### **6\. Competitive Landscape & Differentiators**

AxiomPay is not competing with other protocols; it is filling a critical, unoccupied niche.

| Protocol | Payment Model | Analogy | Best For... | Key Weakness |
| :---- | :---- | :---- | :---- | :---- |
| **AxiomPay (Our Solution)** | **Stateful Escrow** | **Utility Meter** | Continuous services (compute, data feeds, IoT, banking). | **Capital Inefficient.** Payer must lock 100% of funds upfront. |
| **Coinbase x402** | **Stateless Request** | **Toll Booth** | One-off, discrete tasks (single API call, one-time data query). | Inefficient for high-frequency or continuous services. |
| **Superfluid** | **Stateful Stream** | **Subscription** | Open-ended streams (salaries, subscriptions). | **No Provider Guarantee.**  Payer can "go broke" and stop the stream, creating risk for the provider. |

**Our Unique Value Proposition:** AxiomPay is the *only* protocol that provides a **cryptographically-verifiable, upfront guarantee** for the service provider, making it the ideal choice for high-trust, continuous agent interactions.

Furthermore, AxiomPay is designed to be a **settlement rail for Google's Agent Payments Protocol (AP2)**. While AP2 provides the "intent" and "handshake" layer, it needs a protocol to handle the actual settlement. AxiomPay serves as the stateful, session-based rail for AP2, while x402 serves as the stateless, request-based rail.

### **7\. Business Model**

Our monetization strategy is simple, transparent, and aligned with our users.

1. **Protocol Fee:** We will implement a small, non-intrusive protocol fee on the withdrawFromStream function (e.g., 0.05% \- 0.10%). This fee is only paid by the service *provider* upon successfully *earning* revenue. This is a 30-60x lower take rate than traditional payment processors.  
2. **SDK & Tooling:** Offer a "pro" version of the AxiomPay SDK with advanced features like analytics, agent monitoring, and enterprise-grade support.  
3. **Marketplace Curation:** As the ServiceRegistry grows, we can offer paid "curation" or "verification" services for agents, creating a trusted marketplace.

### **8\. Go-to-Market Strategy & Roadmap**

**Phase 1: Protocol Development & Audit (Q1-Q2 2026\)**

* Develop and test AxiomStream.sol and ServiceRegistry.sol contracts.  
* Complete two independent, public security audits.  
* Deploy contracts to Base and Optimism mainnets.

**Phase 2: SDK & Developer Onboarding (Q3 2026\)**

* Release the v1.0 AxiomPay SDK for Python and JavaScript.  
* Publish comprehensive documentation, tutorials, and examples.  
* Launch a **Developer Grant Program** to incentivize AI and DePIN (Decentralized Physical Infrastructure) projects to build on the protocol.

**Phase 3: Ecosystem & Partnership Growth (Q4 2026 \- 2027\)**

* Integrate with Google's AP2, positioning AxiomPay as the primary "stateful settlement" option.  
* Partner with AI agent development platforms (e.g., LangChain, Autogen) to embed the SDK.  
* Sponsor hackathons and build a strong developer community to drive grassroots adoption.

### **9\. Conclusion**

The M2M economy is inevitable. The protocols we build today will define the next generation of digital commerce. AxiomPay provides the most critical, missing piece: a **trust-minimized, stateful, and efficient payment rail** that allows autonomous agents to transact for continuous services securely. By prioritizing provider-side trust and capital-in-session, AxiomPay unlocks the high-value use cases—from decentralized compute to real-time financial settlement—that will power the autonomous future.