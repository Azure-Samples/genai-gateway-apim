/**
 * API endpoint for the search service
 * @constant {string}
 */
const API_URL = 'http://localhost:1337/search';

// DOM Element references
const sendButton = document.getElementById('sendButton');
const inputBox = document.getElementById('inputBox');
const responseArea = document.getElementById('chat');
const spinner = document.getElementById('spinner');

/**
 * Adds a message to the chat container with optional location information
 * @param {string} username - The sender's username ('YOU' or 'SERVER')
 * @param {string} message - The message content to display
 * @param {string|null} location - Optional server location information
 * @returns {void}
 */
function addMessage(username, message, location = null) {
  const div = document.createElement('div');
  div.classList.add('message');

  const usernameSpan = document.createElement('span');
  usernameSpan.classList.add('username');
  usernameSpan.innerText = `${username}: `;

  const textSpan = document.createElement('span');
  textSpan.classList.add('text');
  textSpan.innerText = message;

  div.appendChild(usernameSpan);
  div.appendChild(textSpan);

  if (location) {
    const locationInfo = document.createElement('p');
    locationInfo.classList.add('location');
    locationInfo.innerText = `Server on: ${location}`;
    div.appendChild(locationInfo);
  }

  if (username === 'YOU') {
    div.classList.add('you');
  } else {
    div.classList.add('server');
  }

  responseArea.appendChild(div);
  responseArea.scrollTop = responseArea.scrollHeight; // Auto-scroll to bottom
}

/**
 * Event handler for the send button click
 * Sends the user's message to the server and displays the response
 * @async
 * @returns {Promise<void>}
 */
sendButton.addEventListener('click', async () => {
  const message = inputBox.value.trim();
  if (message) {
    addMessage('YOU', message);
    inputBox.value = '';
    spinner.style.display = 'block';

    try {
      /**
       * @type {Response}
       */
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message })
      });

      if (!response.ok) {
        throw new Error(`HTTP error! Status: ${response.status}`);
      }

      /**
       * @typedef {Object} ServerResponse
       * @property {string} message - The server's response message
       * @property {string} location - The server's location
       */
      const data = await response.json();
      console.log('[SERVER RESPONSE]', data);

      addMessage('SERVER', data.message, data.location);
    } catch (error) {
      console.error('Error:', error);
      addMessage('SERVER', 'An error occurred while processing your request.');
    } finally {
      spinner.style.display = 'none';
    }
  }
});
