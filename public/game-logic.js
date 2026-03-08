// Game data and logic for Guess Who on Avalanche
const QUESTIONS = [
  { id: 'gender', attr: 'gender', text: 'Am I a man?' },
  { id: 'age_20_35', attr: 'age_20_35', text: 'Am I between 20 and 35 years old?' },
  { id: 'age_36_50', attr: 'age_36_50', text: 'Am I between 36 and 50 years old?' },
  { id: 'age_51_plus', attr: 'age_51_plus', text: 'Am I older than 50?' },
  { id: 'alive2026', attr: 'alive2026', text: 'Am I alive in 2026?' },
  { id: 'rock', attr: 'rock', text: 'Do I sing rock music?' },
  { id: 'pop', attr: 'pop', text: 'Do I sing pop music?' },
  { id: 'rap', attr: 'rap', text: 'Do I perform rap or hip-hop?' },
  { id: 'american', attr: 'american', text: 'Am I American?' },
  { id: 'british', attr: 'british', text: 'Am I British?' },
  { id: 'guitarist', attr: 'guitarist', text: 'Do I play guitar on stage?' },
  { id: 'pianist', attr: 'pianist', text: 'Do I play piano or keyboards?' },
  { id: 'beard', attr: 'beard', text: 'Do I have a beard?' },
  { id: 'glasses', attr: 'glasses', text: 'Do I wear glasses?' }
];

// Global game state
let characters = [];
let remainingIds = [];
let askedQuestions = [];
let currentQuestion = null;
let mySecretCharacterId = null;

// Initialize game
async function initGame() {
  await loadCharacters();
  remainingIds = characters.map(c => c.id);
  renderBoard();
}

// Load characters from JSON
async function loadCharacters() {
  try {
    const response = await fetch('characters_25.json');
    characters = await response.json();
  } catch (error) {
    console.error('Failed to load characters:', error);
  }
}

// Apply Yes/No answer to filter characters
function applyAnswer(answerYes) {
  if (!currentQuestion) return;
  
  remainingIds = remainingIds.filter(id => {
    const value = characters[id][currentQuestion.attr];
    if (value === 2) return true;  // Unknown - don't eliminate
    return answerYes ? (value === 1) : (value === 0);
  });
  
  renderBoard();
  askedQuestions.push(currentQuestion.id);
  currentQuestion = null;
  updateUI();
}

// Pick next question (random from unasked)
function pickNextQuestion() {
  const available = QUESTIONS.filter(q => !askedQuestions.includes(q.id));
  if (available.length === 0) return null;
  
  currentQuestion = available[Math.floor(Math.random() * available.length)];
  askedQuestions.push(currentQuestion.id);
  return currentQuestion;
}

// Render character board with elimination visual
function renderBoard() {
  const board = document.getElementById('board');
  if (!board) return;
  
  board.innerHTML = '';
  characters.forEach(character => {
    const div = document.createElement('div');
    div.className = 'character';
    div.dataset.id = character.id;
    
    if (!remainingIds.includes(character.id)) {
      div.classList.add('eliminated');
    } else if (character.id === mySecretCharacterId) {
      div.classList.add('secret-highlight');
    }
    
    div.innerHTML = `
      <div class="character-emoji">🎤</div>
      <div class="character-name">${character.name}</div>
    `;
    
    div.addEventListener('click', () => selectGuess(character.id));
    board.appendChild(div);
  });
  
  updateStats();
}

// Update game stats
function updateStats() {
  const statsEl = document.getElementById('stats');
  if (statsEl) {
    const remainingCount = remainingIds.length;
    statsEl.textContent = `${remainingCount} characters remaining`;
    
    if (remainingCount <= 3) {
      document.getElementById('guessBtn')?.classList.add('pulse');
    }
  }
}

// Select character for guess
function selectGuess(characterId) {
  if (remainingIds.includes(characterId) && mySecretCharacterId === characterId) {
    showWin();
  } else {
    showLose(characterId);
  }
}

// UI control functions
function showQuestion() {
  if (!currentQuestion) {
    currentQuestion = pickNextQuestion();
  }
  
  const questionEl = document.getElementById('currentQuestion');
  if (questionEl && currentQuestion) {
    questionEl.textContent = currentQuestion.text;
    document.getElementById('questionSection')?.classList.remove('hidden');
  }
}

function hideQuestion() {
  document.getElementById('questionSection')?.classList.add('hidden');
  currentQuestion = null;
}

function setSecretCharacter(characterId) {
  mySecretCharacterId = characterId;
  renderBoard();
}

// Game win/lose
function showWin() {
  alert('WINNER! You guessed correctly!');
}

function showLose(wrongId) {
  alert(`Wrong guess! It was not ${characters[wrongId].name}`);
}

// Reset game
function resetGame() {
  remainingIds = characters.map(c => c.id);
  askedQuestions = [];
  currentQuestion = null;
  renderBoard();
}

// Initialize when DOM loads
document.addEventListener('DOMContentLoaded', initGame);
