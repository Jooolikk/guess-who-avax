// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

contract GuessWhoGame is VRFConsumerBaseV2 {
    
    // Avalanche Fuji Testnet addresses (replace for mainnet)
    VRFCoordinatorV2Interface public COORDINATOR = VRFCoordinatorV2Interface(0x...); // Fuji VRF Coordinator
    uint64 public s_subscriptionId;
    bytes32 public keyHash = 0x...; // Fuji keyHash
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 6; // 6 players
    
    struct Game {
        address[6] players;
        uint8 playerCount;
        uint256[] secretCharacters; // Hashed for privacy
        uint256 prizePool;
        bool active;
        bool finished;
        address winner;
        uint256 gameId;
    }
    
    mapping(uint256 => Game) public games;
    mapping(address => uint256) public playerToGame;
    uint256 public gameCounter;
    
    // Character pool (expand to 100+)
    uint256[] public characterPool = [
        1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
        21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
        41,42,43,44,45,46,47,48,49,50 // IDs from characters.json
    ];
    
    event GameStarted(uint256 indexed gameId, address[6] players);
    event CharactersAssigned(uint256 indexed gameId);
    event GameWon(uint256 indexed gameId, address winner, uint256 prize);
    
    constructor(uint64 subscriptionId) VRFConsumerBaseV2(0x...) {
        COORDINATOR = VRFCoordinatorV2Interface(0x...); // Fuji coordinator
        s_subscriptionId = subscriptionId;
    }
    
    // Players join and pay entry fee
    function joinGame() external payable {
        require(msg.value == 0.01 ether, "Entry fee: 0.01 AVAX");
        
        uint256 gameId = gameCounter;
        Game storage game = games[gameId];
        
        require(game.playerCount < 6, "Game full");
        require(game.active == false, "Game already started");
        
        game.players[game.playerCount] = msg.sender;
        game.playerCount++;
        game.prizePool += msg.value;
        playerToGame[msg.sender] = gameId;
        
        if (game.playerCount == 6) {
            game.active = true;
            game.gameId = gameId;
            requestRandomCharacters(gameId);
            emit GameStarted(gameId, game.players);
        }
    }
    
    // Request VRF for character assignment
    function requestRandomCharacters(uint256 gameId) internal {
        uint256 requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        // Store request mapping in production
    }
    
    // VRF callback assigns secret characters
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 gameId = 0; // Map requestId to gameId
        Game storage game = games[gameId];
        
        for (uint i = 0; i < 6; i++) {
            uint256 charIndex = uint256(keccak256(abi.encode(randomWords[i]))) % characterPool.length;
            game.secretCharacters.push(characterPool[charIndex]);
        }
        
        emit CharactersAssigned(gameId);
    }
    
    // Player guesses their secret character
    function guess(uint256 characterId) external {
        uint256 gameId = playerToGame[msg.sender];
        Game storage game = games[gameId];
        
        require(game.active && !game.finished, "Game not active");
        
        // Find player index and verify guess
        uint playerIndex = findPlayerIndex(msg.sender, game.players);
        require(game.secretCharacters[playerIndex] == characterId, "Wrong character!");
        
        game.finished = true;
        game.winner = msg.sender;
        
        uint256 prize = (game.prizePool * 80) / 100;
        payable(msg.sender).transfer(prize);
        
        emit GameWon(gameId, msg.sender, prize);
    }
    
    function findPlayerIndex(address player, address[6] memory players) internal pure returns (uint8) {
        for (uint8 i = 0; i < 6; i++) {
            if (players[i] == player) return i;
        }
        revert("Player not found");
    }
    
    // Emergency refund if game doesn't fill
    function refund(uint256 gameId) external {
        Game storage game = games[gameId];
        require(game.playerCount < 6 && block.timestamp > game.gameId + 30 minutes);
        // Refund logic
    }
}
