// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract GuessWhoGame is VRFConsumerBaseV2 {
    
    // Avalanche Fuji Testnet - Chainlink VRF v2.5 addresses
    VRFCoordinatorV2Interface public immutable COORDINATOR;
    uint64 public immutable s_subscriptionId;
    bytes32 public immutable keyHash;
    uint32 public constant CALLBACK_GAS_LIMIT = 100000;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 6; // 6 players
    
    struct Game {
        address[6] players;
        uint8 playerCount;
        uint256[] secretCharacters; // Private character IDs
        uint256 prizePool;
        bool active;
        bool finished;
        address winner;
        uint256 requestId;
    }
    
    mapping(uint256 => Game) public games; // gameId => Game
    mapping(uint256 => uint256) public requestToGameId; // VRF requestId => gameId
    mapping(address => uint256) public playerToGame; // player => gameId
    
    uint256 public gameCounter;
    
    // Character pool - 50 characters (expandable)
    uint256[] public characterPool = [
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
        21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48,49,50
    ];
    
    // Events
    event GameStarted(uint256 indexed gameId, address[6] players);
    event CharactersAssigned(uint256 indexed gameId);
    event GameWon(uint256 indexed gameId, address winner, uint256 prize);
    
    // Fuji Testnet addresses
    constructor(uint64 subscriptionId) 
        VRFConsumerBaseV2(0xE40895D055bccd2053dD0638C9695E326152b1A4) // Fuji VRF Coordinator v2.5
    {
        COORDINATOR = VRFCoordinatorV2Interface(0xE40895D055bccd2053dD0638C9695E326152b1A4);
        s_subscriptionId = subscriptionId;
        // 200 gwei keyHash for Fuji (from Chain.link docs)
        keyHash = 0xea7f56be19583eeb8255aa79f16d8bd8a64cedf68e42fefee1c9ac5372b1a102;
    }
    
    /*** GAME FLOW ***/
    
    // 1. Players join and pay entry fee (0.01 AVAX)
    function joinGame() external payable {
        require(msg.value == 0.01 ether, "Entry: 0.01 AVAX exactly");
        
        uint256 gameId = gameCounter;
        Game storage game = games[gameId];
        
        require(game.playerCount < 6, "Game lobby full (max 6 players)");
        require(!game.active, "Game already started");
        
        // Assign player to slot
        game.players[game.playerCount] = msg.sender;
        game.playerCount++;
        game.prizePool += msg.value;
        
        playerToGame[msg.sender] = gameId;
        
        // Auto-start when 6 players join
        if (game.playerCount == 6) {
            game.active = true;
            uint256 requestId = COORDINATOR.requestRandomWords(
                keyHash,
                s_subscriptionId,
                REQUEST_CONFIRMATIONS,
                CALLBACK_GAS_LIMIT,
                NUM_WORDS
            );
            game.requestId = requestId;
            requestToGameId[requestId] = gameId;
            gameCounter++;
            
            emit GameStarted(gameId, game.players);
        }
    }
    
    // 2. VRF callback - assign secret characters
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 gameId = requestToGameId[requestId];
        Game storage game = games[gameId];
        
        require(game.active && game.playerCount == 6, "Invalid game state");
        
        // Assign unique random characters to each player
        for (uint i = 0; i < 6; i++) {
            uint256 randomIndex = uint256(keccak256(abi.encode(randomWords[i], block.timestamp))) % characterPool.length;
            game.secretCharacters.push(characterPool[randomIndex]);
        }
        
        emit CharactersAssigned(gameId);
    }
    
    // 3. Player guesses their secret character
    function guess(uint256 characterId) external {
        uint256 gameId = playerToGameId[msg.sender];
        require(gameId != 0, "Not in active game");
        
        Game storage game = games[gameId];
        require(game.active && !game.finished, "Game not active for guessing");
        
        // Verify this is the correct player and guess
        uint8 playerIndex = findPlayerIndex(msg.sender, game.players);
        require(game.secretCharacters[playerIndex] == characterId, "Wrong character ID!");
        
        // Game over - payout winner
        game.finished = true;
        game.winner = msg.sender;
        
        uint256 prize = (game.prizePool * 80) / 100; // 80% to winner
        uint256 fee = game.prizePool - prize; // 20% fee/reserve
        
        payable(msg.sender).transfer(prize);
        
        emit GameWon(gameId, msg.sender, prize);
    }
    
    // 4. Utility: Find player slot
    function findPlayerIndex(address player, address[6] memory players) internal pure returns (uint8) {
        for (uint8 i = 0; i < 6; i++) {
            if (players[i] == player) {
                return i;
            }
        }
        revert("Player not found in game");
    }
    
    // 5. View functions
    function getGameInfo(uint256 gameId) external view returns (Game memory) {
        return games[gameId];
    }
    
    function getPlayerGame(address player) external view returns (uint256) {
        return playerToGame[player];
    }
    
    // 6. Emergency refund (if game doesn't fill)
    function claimRefund(uint256 gameId) external {
        Game storage game = games[gameId];
        require(block.timestamp > (gameCounter * 1 hours), "Wait 1 hour before refund");
        require(game.playerCount < 6, "Game completed");
        
        uint256 refundAmount = 0.01 ether;
        payable(msg.sender).transfer(refundAmount);
        game.prizePool -= refundAmount;
    }
    
    receive() external payable {}
}

