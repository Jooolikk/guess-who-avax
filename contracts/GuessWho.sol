// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title GuessWhoGame
 * @notice 6-player on-chain lobby for the Guess Who prototype on Avalanche Fuji.
 *
 * Flow:
 * - 6 players join a lobby, each paying 0.01 AVAX.
 * - When the lobby is full, the contract requests randomness from Chainlink VRF v2.5.
 * - VRF returns:
 *      randomWords[0] → charactersSeed (frontend uses it to assign unique characters).
 *      randomWords[1] → firstPlayerIndex (0–5, who starts first).
 * - All questioning / bot logic happens off-chain in the UI.
 * - When the game is finished, the winner calls claimWin(gameId) and receives 80% of the pool.
 *
 * NOTE: This is an MVP for demo purposes. There is no on-chain verification of the winner.
 */
contract GuessWhoGame is VRFConsumerBaseV2 {
    // ------------------------------------------------------------
    // Chainlink VRF configuration for Avalanche Fuji (v2.5)
    // ------------------------------------------------------------

    // VRF Coordinator for Avalanche Fuji
    address public constant VRF_COORDINATOR = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;

    // 300 gwei key hash for Avalanche Fuji
    bytes32 public constant KEY_HASH =
        0xc799bd1e3bd4d1a41cd4968997a4e03dfd2a3c7c04b695881138580163f42887;

    // Fixed subscription ID you created on vrf.chain.link for Fuji
    uint64 public constant SUBSCRIPTION_ID =
        23986757496573613453045326593651429957236106211255091330146193048322870466599;

    VRFCoordinatorV2Interface public immutable COORDINATOR;

    uint32 public constant CALLBACK_GAS_LIMIT = 250000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 2; // [0] charactersSeed, [1] firstPlayerIndex

    // requestId => gameId
    mapping(uint256 => uint256) private requestIdToGameId;

    // ------------------------------------------------------------
    // Game configuration
    // ------------------------------------------------------------

    uint256 public constant ENTRY_FEE = 0.01 ether;
    uint8 public constant MAX_PLAYERS = 6;

    enum GameStatus {
        WaitingForPlayers,
        WaitingForRandomness,
        Active,
        Finished,
        Cancelled
    }

    struct Game {
        uint256 id;
        GameStatus status;
        address creator;
        uint8 playerCount;
        address[MAX_PLAYERS] players;
        uint256 prizePool;
        uint256 vrfRequestId;
        uint256 charactersSeed;
        uint8 firstPlayerIndex; // 0–5 index in players[]
        address winner;
        uint256 prizePaid;
        uint256 createdAt;
    }

    uint256 public gameCounter;
    mapping(uint256 => Game) public games;

    /// @dev Player can only be in one open game at a time.
    mapping(address => uint256) public playerToGameId;

    address public immutable owner;

    // ------------------------------------------------------------
    // Events
    // ------------------------------------------------------------

    event GameCreated(uint256 indexed gameId, address indexed creator);
    event PlayerJoined(uint256 indexed gameId, address indexed player, uint8 playerIndex);
    event GameReady(uint256 indexed gameId, uint256 requestId);
    event CharactersAssigned(
        uint256 indexed gameId,
        uint256 charactersSeed,
        uint8 firstPlayerIndex
    );
    event WinnerSet(uint256 indexed gameId, address indexed winner, uint256 prize);
    event GameCancelled(uint256 indexed gameId);
    event Refunded(uint256 indexed gameId, address indexed player, uint256 amount);

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------

    constructor() VRFConsumerBaseV2(VRF_COORDINATOR) {
        owner = msg.sender;
        COORDINATOR = VRFCoordinatorV2Interface(VRF_COORDINATOR);
    }

    // ------------------------------------------------------------
    // Game lifecycle
    // ------------------------------------------------------------

    /**
     * @notice Creates a new lobby and joins the creator as the first player.
     * @return gameId The id of the created game.
     */
    function createGame() external payable returns (uint256 gameId) {
        require(msg.value == ENTRY_FEE, "Invalid entry fee");
        require(playerToGameId[msg.sender] == 0, "Already in a game");

        gameCounter += 1;
        gameId = gameCounter;

        Game storage game = games[gameId];
        game.id = gameId;
        game.status = GameStatus.WaitingForPlayers;
        game.creator = msg.sender;
        game.playerCount = 1;
        game.players[0] = msg.sender;
        game.prizePool = msg.value;
        game.createdAt = block.timestamp;

        playerToGameId[msg.sender] = gameId;

        emit GameCreated(gameId, msg.sender);
        emit PlayerJoined(gameId, msg.sender, 0);
    }

    /**
     * @notice Joins an existing lobby until 6 players are present.
     *         When the 6th player joins, a VRF request is sent.
     */
    function joinGame(uint256 gameId) external payable {
        Game storage game = games[gameId];
        require(game.id != 0, "Game does not exist");
        require(game.status == GameStatus.WaitingForPlayers, "Game already started");
        require(game.playerCount < MAX_PLAYERS, "Game is full");
        require(msg.value == ENTRY_FEE, "Invalid entry fee");
        require(playerToGameId[msg.sender] == 0, "Already in a game");

        uint8 index = game.playerCount;
        game.players[index] = msg.sender;
        game.playerCount += 1;
        game.prizePool += msg.value;

        playerToGameId[msg.sender] = gameId;

        emit PlayerJoined(gameId, msg.sender, index);

        if (game.playerCount == MAX_PLAYERS) {
            _requestRandomness(gameId);
        }
    }

    /**
     * @dev Internal VRF request when lobby is filled.
     */
    function _requestRandomness(uint256 gameId) internal {
        Game storage game = games[gameId];
        require(game.playerCount == MAX_PLAYERS, "Not enough players");
        require(game.status == GameStatus.WaitingForPlayers, "Wrong status");

        uint256 requestId = COORDINATOR.requestRandomWords(
            KEY_HASH,
            SUBSCRIPTION_ID,
            REQUEST_CONFIRMATIONS,
            CALLBACK_GAS_LIMIT,
            NUM_WORDS
        );

        requestIdToGameId[requestId] = gameId;
        game.vrfRequestId = requestId;
        game.status = GameStatus.WaitingForRandomness;

        emit GameReady(gameId, requestId);
    }

    /**
     * @notice VRF callback: assigns characters seed and first player index.
     *         Characters themselves are resolved off-chain using charactersSeed.
     */
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 gameId = requestIdToGameId[requestId];
        Game storage game = games[gameId];
        require(game.id != 0, "Unknown game");
        require(game.status == GameStatus.WaitingForRandomness, "Not waiting for randomness");

        // First random word is a big seed used by the frontend to assign character ids
        uint256 charactersSeed = randomWords[0];

        // Second word picks who starts: 0..5 index
        uint8 firstPlayerIndex = uint8(randomWords[1] % MAX_PLAYERS);

        game.charactersSeed = charactersSeed;
        game.firstPlayerIndex = firstPlayerIndex;
        game.status = GameStatus.Active;

        emit CharactersAssigned(gameId, charactersSeed, firstPlayerIndex);
    }

    /**
     * @notice Called by the winner after the round is finished.
     *         The contract trusts the caller for MVP purposes.
     *         In production this should be replaced with on-chain verification.
     */
    function claimWin(uint256 gameId) external {
        Game storage game = games[gameId];
        require(game.status == GameStatus.Active, "Game not active");
        require(_isPlayerInGame(gameId, msg.sender), "Not a player");
        require(game.winner == address(0), "Winner already set");

        uint256 prize = (game.prizePool * 80) / 100;
        uint256 fee = game.prizePool - prize;

        game.winner = msg.sender;
        game.prizePaid = prize;
        game.status = GameStatus.Finished;

        _clearPlayers(gameId);

        (bool ok1, ) = msg.sender.call{value: prize}("");
        require(ok1, "Prize transfer failed");

        if (fee > 0) {
            (bool ok2, ) = owner.call{value: fee}("");
            require(ok2, "Fee transfer failed");
        }

        emit WinnerSet(gameId, msg.sender, prize);
    }

    /**
     * @notice Cancel the game and refund players if VRF takes too long
     *         or lobby never fills. Only the creator or owner can cancel.
     */
    function cancelGame(uint256 gameId) external {
        Game storage game = games[gameId];
        require(game.id != 0, "Game does not exist");
        require(msg.sender == game.creator || msg.sender == owner, "Not allowed");
        require(
            game.status == GameStatus.WaitingForPlayers ||
                game.status == GameStatus.WaitingForRandomness,
            "Cannot cancel now"
        );

        game.status = GameStatus.Cancelled;

        for (uint8 i = 0; i < game.playerCount; i++) {
            address p = game.players[i];
            if (p != address(0)) {
                playerToGameId[p] = 0;
                (bool ok, ) = p.call{value: ENTRY_FEE}("");
                if (ok) {
                    emit Refunded(gameId, p, ENTRY_FEE);
                }
            }
        }

        emit GameCancelled(gameId);
    }

    // ------------------------------------------------------------
    // View helpers
    // ------------------------------------------------------------

    function getPlayers(
        uint256 gameId
    ) external view returns (address[MAX_PLAYERS] memory) {
        return games[gameId].players;
    }

    function _isPlayerInGame(uint256 gameId, address player) internal view returns (bool) {
        Game storage game = games[gameId];
        for (uint8 i = 0; i < game.playerCount; i++) {
            if (game.players[i] == player) return true;
        }
        return false;
    }

    function _clearPlayers(uint256 gameId) internal {
        Game storage game = games[gameId];
        for (uint8 i = 0; i < game.playerCount; i++) {
            address p = game.players[i];
            if (p != address(0)) {
                playerToGameId[p] = 0;
            }
        }
    }

    // ------------------------------------------------------------
    // Admin
    // ------------------------------------------------------------

    function withdrawTips() external {
        require(msg.sender == owner, "Only owner");
        uint256 bal = address(this).balance;
        (bool ok, ) = owner.call{value: bal}("");
        require(ok, "Withdraw failed");
    }

    receive() external payable {}
}
