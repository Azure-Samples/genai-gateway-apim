# Azure APIM Azure Open AI sample

This sample project demonstrates how to use Azure API Management and Azure OpenAI to create a simple chatbot.

## Quick Start

### Prerequisites

- Install [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- Install [Node.js](https://nodejs.org/en/download/)

## 1. Deploying the project

Run the following command to login to `azd`:

```bash
azd auth login
```

Deploy the project to Azure by running the following command:

```bash
azd up
```

> NOTE: You'll be asked to select:
> - An environment name. You can enter any value you'd like. For example: "apim-genai". The value serves as a prefix for naming resources in your deployment.
> - The Azure subscription to use.
> - An Azure location.

### Inspect environment variables

After running the `azd up` command, an environment file will be generated for you at `src/.env`. Here's what's in the auto-generated file:

```bash
SUBSCRIPTION_KEY="<Your Subscription Key>"
DEPLOYMENT_ID="<Your Deployment ID>"
API_VERSION="<Your API Version>"
APIM_ENDPOINT="<Your APIM Endpoint>"
API_SUFFIX="<Your API Suffix>"
```

**Finding values using the Azure portal:**

If you'd like to find the values in the `.env` yourself, you can follow these steps:
    
|Value  |Instruction  |
|---------|---------|
|SUBSCRIPTION_KEY     | Navigate to portal.azure.com -> Select rg -> select APIM instance -> Go to APIs/Subscriptions -> Click show/hide keys on first row (Built-in all-access) -> copy Primary key        |
| DEPLOYMENT_ID | Navigate to portal.azure.com -> Select rg -> Select 1st OpenAI instance -> Go to Resource Management/Mode deployments -> Click on Manage Deployments to open Azure AI Studio -> Copy Deployment name |
| API_VERSION | Navigate to <https://learn.microsoft.com/azure/ai-services/openai/reference#completions>, Copy most recent Supported versions = 2024-02-01 |
| APIM_ENDPOINT | Navigate to portal.azure.com -> Select rg -> Select APIM instance -> Go to Overview -> Copy Gateway URL |
| API_SUFFIX | Navigate to portal.azure.com -> Select rg -> Select APIM instance -> Navigate to APIs/APIs -> open myAPI -> Go to settings -> Copy API URL suffix |

## 2. Run the project locally

Once the Azure services have been deployed, you can run the app by running the below commands:

```bash
cd src
npm install
npm start
```

This will start the app on `http://localhost:3000` and the API is available at `http:localhost:1337`.

## 3. Deprovision the project

Once you're done, you can remove all deployed resources using the following command:

```bash
azd down --purge
```

The preceding command removes all provisoned resources. The `--purge` hard deletes all resources.

> NOTE: Some resources on Azure are only soft deleted for performance reasons and can be retrieved. By using `--purge` resources are hard deleted and cannot be retrieved.


## What's in this repo

|What  |Description  | Link |
|---------|---------|--|
|Frontend     | a frontend consisting of a `index.html` and `app.js` | [Link](./src/web/)        |
|Backend     | A backend written in Node.js and Express framework | [Link](./src/api/)        |
|Bicep     | Bicep files containing the needed information to deploy resources and configure them as needed        | [Link](./infra) |

## Demo

![App running](./apim.png)

## Documentation

The documentation for this project is available in the [DOC.md](./DOC.md) file.
