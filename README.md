# Azure APIM Azure Open AI sample

This is a sample project that demonstrates how to use Azure API Management and Azure Open AI to create a simple chatbot.

## Quick Start

### Prerequisites

- Install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- Install [Node.js](https://nodejs.org/en/download/)

## 1. Deploying the project

To deploy the project run the following commands:

```bash
az login
az account set --subscription <Your Subscription ID>
az group create -n <Your Resource Group Name> -l <Your Resource Group Location>
az deployment group create -f main.bicep -g <Your Resource Group Name>
```

## 2. Set environment variables

Set the environment variables in the `.env` file, it should look like this:

```bash
SUBSCRIPTION_KEY="<Your Subscription Key>"
DEPLOYMENT_ID="<Your Deployment ID>"
API_VERSION="<Your API Version>"
APIM_ENDPOINT="<Your APIM Endpoint>"
API_SUFFIX="<Your API Suffix>"
```

## 3. Run the project locally

Once you have set the environment variables, you can run the app by running the below commands:

```bash
npm install
npm start
```

This will start the app on `http://localhost:3000` and the API is available at `http:localhost:5000`.

## What's in this repo

|What  |Description  | Link |
|---------|---------|--|
|Frontend     | a frontend consisting of a `index.html` and `app.js` | [Link](./src/web/)        |
|Backend     | A backend written in Node.js and Express framework | [Link](./src/api/)        |
|Bicep     | Bicep files containing the needed information to deploy resources and configure them as needed        | [Link](./main.bicep) |

## Demo

![App running](./apim.png)

## Documentation

The documentation for this project is available in the [DOC.md](./DOC.md) file.