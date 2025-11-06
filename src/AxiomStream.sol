// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AxiomStream
 * @author AxiomPay
 * @notice The stateful settlement protocol for the autonomous agent economy
 * @dev Implements a provider-verifiable escrow model for time-based payment streams
 * 
 * Core Features:
 * - Payer locks 100% of session funds upfront in escrow
 * - Provider can verify funds are locked on-chain before service delivery
 * - Provider earns funds per-second and can withdraw at any time
 * - Payer can cancel and get refunded for unused time
 * - Protocol fees on provider earnings (configurable 0.05-0.10%)
 */
contract AxiomStream is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Represents a payment stream session between a payer and provider
     * @param payer The agent paying for the service
     * @param provider The agent providing the service
     * @param token The ERC-20 token being streamed (e.g., USDC)
     * @param ratePerSecond The amount of tokens earned per second by the provider
     * @param startTime The block.timestamp when the stream began
     * @param duration The total number of seconds funded
     * @param totalAmount The total amount locked in escrow
     * @param withdrawnAmount Total tokens already pulled by the provider
     * @param stopped Whether the stream has been stopped
     */
    struct Stream {
        address payer;
        address provider;
        IERC20 token;
        uint256 ratePerSecond;
        uint256 startTime;
        uint256 duration;
        uint256 totalAmount;
        uint256 withdrawnAmount;
        bool stopped;
    }

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping from streamId to Stream struct
    mapping(uint256 => Stream) public streams;

    /// @notice Counter for generating unique stream IDs
    uint256 public nextStreamId;

    /// @notice Protocol fee in basis points (e.g., 10 = 0.10%)
    uint256 public protocolFeeBps;

    /// @notice Maximum protocol fee (1% = 100 bps)
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 100;

    /// @notice Basis points denominator (10000 = 100%)
    uint256 public constant BPS_DENOMINATOR = 10000;

    /// @notice Accumulated protocol fees per token
    mapping(IERC20 => uint256) public accumulatedFees;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when a new stream is started
     * @param streamId The unique identifier for the stream
     * @param payer The address paying for the service
     * @param provider The address providing the service
     * @param token The ERC-20 token being used
     * @param totalAmount The total amount locked in escrow
     * @param ratePerSecond The rate of payment per second
     * @param duration The duration of the stream in seconds
     */
    event StreamStarted(
        uint256 indexed streamId,
        address indexed payer,
        address indexed provider,
        address token,
        uint256 totalAmount,
        uint256 ratePerSecond,
        uint256 duration
    );

    /**
     * @notice Emitted when a provider withdraws from a stream
     * @param streamId The stream being withdrawn from
     * @param provider The provider withdrawing
     * @param amount The amount withdrawn (after fees)
     * @param fee The protocol fee collected
     */
    event StreamWithdrawn(
        uint256 indexed streamId,
        address indexed provider,
        uint256 amount,
        uint256 fee
    );

    /**
     * @notice Emitted when a stream is stopped early
     * @param streamId The stream being stopped
     * @param payer The payer who stopped the stream
     * @param providerAmount The amount earned by provider
     * @param payerRefund The amount refunded to payer
     * @param fee The protocol fee collected
     */
    event StreamStopped(
        uint256 indexed streamId,
        address indexed payer,
        uint256 providerAmount,
        uint256 payerRefund,
        uint256 fee
    );

    /**
     * @notice Emitted when protocol fee is updated
     * @param oldFeeBps The previous fee in basis points
     * @param newFeeBps The new fee in basis points
     */
    event ProtocolFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    /**
     * @notice Emitted when protocol fees are withdrawn
     * @param token The token withdrawn
     * @param amount The amount withdrawn
     * @param recipient The recipient of the fees
     */
    event ProtocolFeesWithdrawn(address indexed token, uint256 amount, address indexed recipient);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidProvider();
    error InvalidToken();
    error InvalidRate();
    error InvalidDuration();
    error InvalidAmount();
    error StreamNotFound();
    error StreamAlreadyStopped();
    error Unauthorized();
    error InsufficientEarned();
    error ExcessiveProtocolFee();
    error NoFeesToWithdraw();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the AxiomStream contract
     * @param _initialOwner The initial owner of the contract
     * @param _protocolFeeBps The initial protocol fee in basis points (e.g., 10 = 0.10%)
     */
    constructor(address _initialOwner, uint256 _protocolFeeBps) Ownable(_initialOwner) {
        if (_protocolFeeBps > MAX_PROTOCOL_FEE_BPS) revert ExcessiveProtocolFee();
        protocolFeeBps = _protocolFeeBps;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Start a new payment stream
     * @dev Payer must have approved this contract to spend `totalAmount` of `token`
     * @param provider The address that will receive the stream
     * @param token The ERC-20 token to be streamed
     * @param ratePerSecond The amount of tokens to stream per second
     * @param duration The duration of the stream in seconds
     * @return streamId The unique identifier for this stream
     */
    function startStream(
        address provider,
        IERC20 token,
        uint256 ratePerSecond,
        uint256 duration
    ) external nonReentrant returns (uint256 streamId) {
        // Validation
        if (provider == address(0)) revert InvalidProvider();
        if (address(token) == address(0)) revert InvalidToken();
        if (ratePerSecond == 0) revert InvalidRate();
        if (duration == 0) revert InvalidDuration();

        // Calculate total amount
        uint256 totalAmount = ratePerSecond * duration;
        if (totalAmount == 0) revert InvalidAmount();

        // Generate stream ID
        streamId = nextStreamId++;

        // Create stream
        streams[streamId] = Stream({
            payer: msg.sender,
            provider: provider,
            token: token,
            ratePerSecond: ratePerSecond,
            startTime: block.timestamp,
            duration: duration,
            totalAmount: totalAmount,
            withdrawnAmount: 0,
            stopped: false
        });

        // Transfer tokens to escrow
        token.safeTransferFrom(msg.sender, address(this), totalAmount);

        emit StreamStarted(
            streamId,
            msg.sender,
            provider,
            address(token),
            totalAmount,
            ratePerSecond,
            duration
        );
    }

    /**
     * @notice Withdraw earned funds from a stream
     * @dev Can only be called by the provider. Collects protocol fees.
     * @param streamId The ID of the stream to withdraw from
     * @return amountAfterFee The amount withdrawn after protocol fees
     */
    function withdrawFromStream(uint256 streamId) 
        external 
        nonReentrant 
        returns (uint256 amountAfterFee) 
    {
        Stream storage stream = streams[streamId];

        // Validation
        if (stream.payer == address(0)) revert StreamNotFound();
        if (msg.sender != stream.provider) revert Unauthorized();

        // Calculate earned amount
        uint256 totalEarned = _calculateEarned(stream);
        uint256 availableToWithdraw = totalEarned - stream.withdrawnAmount;

        if (availableToWithdraw == 0) revert InsufficientEarned();

        // Calculate protocol fee
        uint256 fee = (availableToWithdraw * protocolFeeBps) / BPS_DENOMINATOR;
        amountAfterFee = availableToWithdraw - fee;

        // Update state
        stream.withdrawnAmount += availableToWithdraw;
        accumulatedFees[stream.token] += fee;

        // Transfer tokens to provider
        stream.token.safeTransfer(stream.provider, amountAfterFee);

        emit StreamWithdrawn(streamId, stream.provider, amountAfterFee, fee);
    }

    /**
     * @notice Stop a stream early and refund unused funds to payer
     * @dev Can only be called by the payer. Provider is paid for elapsed time.
     * @param streamId The ID of the stream to stop
     */
    function stopStream(uint256 streamId) external nonReentrant {
        Stream storage stream = streams[streamId];

        // Validation
        if (stream.payer == address(0)) revert StreamNotFound();
        if (msg.sender != stream.payer) revert Unauthorized();
        if (stream.stopped) revert StreamAlreadyStopped();

        // Calculate amounts BEFORE marking as stopped
        uint256 elapsedTime = block.timestamp - stream.startTime;
        if (elapsedTime > stream.duration) {
            elapsedTime = stream.duration;
        }
        
        uint256 totalEarned = elapsedTime * stream.ratePerSecond;
        if (totalEarned > stream.totalAmount) {
            totalEarned = stream.totalAmount;
        }
        
        uint256 providerOwed = totalEarned - stream.withdrawnAmount;
        
        // Calculate protocol fee on provider's earned amount
        uint256 fee = (providerOwed * protocolFeeBps) / BPS_DENOMINATOR;
        uint256 providerAmount = providerOwed - fee;

        // Calculate payer refund
        uint256 payerRefund = stream.totalAmount - totalEarned;

        // Mark as stopped and update state
        stream.stopped = true;
        stream.withdrawnAmount = totalEarned;
        accumulatedFees[stream.token] += fee;

        // Transfer provider's earned amount (if any)
        if (providerAmount > 0) {
            stream.token.safeTransfer(stream.provider, providerAmount);
        }

        // Refund payer's unused amount (if any)
        if (payerRefund > 0) {
            stream.token.safeTransfer(stream.payer, payerRefund);
        }

        emit StreamStopped(streamId, stream.payer, providerAmount, payerRefund, fee);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the current earned amount for a stream
     * @param streamId The ID of the stream
     * @return earned The amount earned by the provider so far
     */
    function getEarned(uint256 streamId) external view returns (uint256 earned) {
        Stream storage stream = streams[streamId];
        if (stream.payer == address(0)) revert StreamNotFound();
        return _calculateEarned(stream);
    }

    /**
     * @notice Get the available amount to withdraw for a stream
     * @param streamId The ID of the stream
     * @return available The amount available to withdraw (before fees)
     */
    function getAvailableToWithdraw(uint256 streamId) 
        external 
        view 
        returns (uint256 available) 
    {
        Stream storage stream = streams[streamId];
        if (stream.payer == address(0)) revert StreamNotFound();
        
        uint256 totalEarned = _calculateEarned(stream);
        return totalEarned - stream.withdrawnAmount;
    }

    /**
     * @notice Get the remaining time in a stream
     * @param streamId The ID of the stream
     * @return remainingTime The remaining time in seconds
     */
    function getRemainingTime(uint256 streamId) 
        external 
        view 
        returns (uint256 remainingTime) 
    {
        Stream storage stream = streams[streamId];
        if (stream.payer == address(0)) revert StreamNotFound();
        
        if (stream.stopped) return 0;
        
        uint256 elapsedTime = block.timestamp - stream.startTime;
        if (elapsedTime >= stream.duration) return 0;
        
        return stream.duration - elapsedTime;
    }

    /**
     * @notice Get full details of a stream
     * @param streamId The ID of the stream
     * @return stream The stream struct
     */
    function getStream(uint256 streamId) external view returns (Stream memory stream) {
        stream = streams[streamId];
        if (stream.payer == address(0)) revert StreamNotFound();
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update the protocol fee
     * @dev Only callable by owner. Fee cannot exceed MAX_PROTOCOL_FEE_BPS (1%)
     * @param newFeeBps The new fee in basis points
     */
    function setProtocolFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_PROTOCOL_FEE_BPS) revert ExcessiveProtocolFee();
        
        uint256 oldFeeBps = protocolFeeBps;
        protocolFeeBps = newFeeBps;
        
        emit ProtocolFeeUpdated(oldFeeBps, newFeeBps);
    }

    /**
     * @notice Withdraw accumulated protocol fees
     * @dev Only callable by owner
     * @param token The token to withdraw fees for
     * @param recipient The address to send fees to
     */
    function withdrawProtocolFees(IERC20 token, address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidProvider();
        
        uint256 amount = accumulatedFees[token];
        if (amount == 0) revert NoFeesToWithdraw();
        
        accumulatedFees[token] = 0;
        token.safeTransfer(recipient, amount);
        
        emit ProtocolFeesWithdrawn(address(token), amount, recipient);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculate the earned amount for a stream
     * @param stream The stream to calculate for
     * @return earned The total amount earned so far
     */
    function _calculateEarned(Stream storage stream) internal view returns (uint256 earned) {
        if (stream.stopped) {
            return stream.withdrawnAmount;
        }

        uint256 elapsedTime = block.timestamp - stream.startTime;
        
        // Cap at duration
        if (elapsedTime > stream.duration) {
            elapsedTime = stream.duration;
        }

        earned = elapsedTime * stream.ratePerSecond;
        
        // Cap at total amount (safety check)
        if (earned > stream.totalAmount) {
            earned = stream.totalAmount;
        }
    }
}
