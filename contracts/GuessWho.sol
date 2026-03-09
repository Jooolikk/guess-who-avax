// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract GuessWhoSimple {
    uint256 public constant ENTRY_FEE = 0.01 ether;
    uint8 public constant MAX_PLAYERS = 6;
    
    struct Game {
        address[6] players;
        uint8 playerCount;
        uint256 prizePool;
        uint256 charactersSeed; 
        uint8 firstPlayer;      
        address winner;
        bool finished;
    }
    
    uint256 public gameCounter;
    mapping(uint256 => Game) public games;
    
    event GameCreated(uint256 indexed gameId, address creator);
    event PlayerJoined(uint256 indexed gameId, uint8 index, address player);
    event GameReady(uint256 indexed gameId, uint256 seed, uint8 firstPlayer);
    event WinnerClaimed(uint256 indexed gameId, address winner, uint256 prize);
    
    function createGame() external payable returns(uint256 gameId) {
        require(msg.value == ENTRY_FEE, "Entry fee: 0.01 AVAX");
        gameCounter++;
        gameId = gameCounter;
        
        Game storage g = games[gameId];
        g.players[0] = msg.sender;
        g.playerCount = 1;
        g.prizePool = msg.value;
        
        emit GameCreated(gameId, msg.sender);
        emit PlayerJoined(gameId, 0, msg.sender);
    }
    
    function joinGame(uint256 gameId) external payable {
        Game storage g = games[gameId];
        require(g.playerCount < MAX_PLAYERS, "Lobby full");
        require(msg.value == ENTRY_FEE, "Entry fee: 0.01 AVAX");
        require(g.players[g.playerCount] == address(0), "Seat taken");
        
        uint8 seat = g.playerCount;
        g.players[seat] = msg.sender;
        g.playerCount++;
        g.prizePool += msg.value;
        
        emit PlayerJoined(gameId, seat, msg.sender);
        
        if(g.playerCount == MAX_PLAYERS) {
            g.charactersSeed = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, gameId)));
            g.firstPlayer = uint8(g.charactersSeed % MAX_PLAYERS);
            emit GameReady(gameId, g.charactersSeed, g.firstPlayer);
        }
    }
    
    function claimWin(uint256 gameId) external {
        Game storage g = games[gameId];
        require(g.playerCount == MAX_PLAYERS, "Not full");
        require(!g.finished, "Game ended");
        require(isPlayer(g, msg.sender), "Not player");
        
        uint256 prize = g.prizePool * 8 / 10;  // 80%
        g.winner = msg.sender;
        g.finished = true;
        
        payable(msg.sender).transfer(prize);  // 80%
        payable(0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045).transfer(g.prizePool - prize);
        
        emit WinnerClaimed(gameId, msg.sender, prize);
    }
    
    function getPlayers(uint256 gameId) external view returns(address[6] memory) {
        return games[gameId].players;
    }
    
    function isPlayer(Game storage g, address player) internal view returns(bool) {
        for(uint8 i=0; i<g.playerCount; i++) {
            if(g.players[i] == player) return true;
        }
        return false;
    }
    
    receive() external payable {}
}
