// express api, should a POST route "search" that takes a message and returns a response
let express = require('express');
let cors = require('cors');
let port = process.env.PORT || 1337;
let apiService = require('./apiService');

const { message } = require('statuses');
let app = express();

app.use(cors());
app.use(express.json());

// express add route
app.get('/', function(req, res) {
    res.json({ message: 'Welcome to this APIM sample, it calls Azure Open AI on POST /search' });
});


app.post('/search',(req, res) => {

    let message = req.body.message;
    console.log('[API] message: ' + message);
    setTimeout(function() {
        apiService.getChatCompletion(message).then(response => {
            res.json({ 
                message: response.text,
                location: response.headers.get('x-ms-region') 
            });
        }).catch(err => {
            res.json({ message: err.message });
        });
    }, 1);
});


app.listen(port, function() {
    console.log('Server started on http://localhost:' + port);
});
