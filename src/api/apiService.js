let dotenv = require('dotenv');

// NOTE: remove this when deploying as it will read from App Service configuration
dotenv.config();

const URL = `${process.env.APIM_ENDPOINT}/${process.env.API_SUFFIX}/deployments/${process.env.DEPLOYMENT_ID}/completions?api-version=${process.env.API_VERSION}`;

const URL_CHAT = `${process.env.APIM_ENDPOINT}/${process.env.API_SUFFIX}/deployments/${process.env.DEPLOYMENT_ID}/chat/completions?api-version=${process.env.API_VERSION}`

console.log("[API] URL: ",URL);

module.exports = {
    getChatCompletion(prompt) {
        let headers = null;

        let body = {
            "model":"gpt-35-turbo","messages":[
                {
                    "role":"system","content":"You're a helpful assistant"
                },
                {
                    "role":"user","content":prompt
                }
            ]};
            return fetch(URL_CHAT, {
                method: "POST",
                headers: {
                    "api-key": process.env.SUBSCRIPTION_KEY,
                    "Content-Type": "application/json"
                },
                body: JSON.stringify(body)
            })
            .then(response => {
                headers = response.headers;
                return response.json();
            }).then(data => { 
                // throw if choices is empty
                console.log("[API] data: ",data);
                console.log("[API] response: ",data.choices[0].message.content);

                if (data.choices.length === 0) {
                    throw new Error('No response');
                } else {
                    console.log("[API] responses: ",data.choices[0].message.content);
                    return { 
                        text : data.choices[0].message.content,
                        headers : headers 
                    };
                }
            });
    },
    getCompletion(prompt) {
        let headers = null;

        let body = {
            "prompt":prompt,
            "max_tokens":400
        };
        
        return fetch(URL, {
            method: "POST",
            headers: {
                "Ocp-Apim-Subscription-Key": process.env.SUBSCRIPTION_KEY,
                "api-key": process.env.SUBSCRIPTION_KEY,
                "Content-Type": "application/json"
            },
            body: JSON.stringify(body)
        }).then(response => {
            headers = response.headers;
            return response.json();
        }).then(data => { 
            // throw if choices is empty
            if (data.choices.length === 0) {
                throw new Error('No completion choices');
            } else {
                console.log("[API] responses: ",data.choices);
                return { 
                    text : data.choices[0].text,
                    headers : headers 
                };
            }
        });
    }
}