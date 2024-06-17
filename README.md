# Step 1: Set Up the Slack App

1. **Create a Slack App**:

   - Go to the [Slack API](https://api.slack.com/apps) page and create a new app.
   - Choose the workspace where you want to develop your app.

2. **Add Features and Functionality**:
   - **OAuth & Permissions**: Add the following scopes under `Bot Token Scope s`:
     - `channels:read`
     - `chat:write`
     - `commands`
   - **Install the App**: Install the app to your workspace and obtain the OAuth access token and signing secret.
   - **Save the OAuth token and signing secret**: These will be used later in the environment variables.

### Step 2: Set Up the Project Directory

1. **Create a new project directory and navigate into it**:

```sh
mkdir slack-music-bot
cd slack-music-bot
```

### Step 3: Create the Lambda Function in Python

1. **Create a directory for the Lambda function**:

```sh
mkdir lambda
cd lambda
```

2. **Create the main Lambda function file `lambda_function.py`and note the slack channel id needs to be your slack channel id**:

```python
import os
import json
import youtube_dl
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler
import subprocess
import tempfile

app = App(signing_secret=os.environ.get("SLACK_SIGNING_SECRET"))

channel_id = "C0717R6ND17"  # Replace with your actual channel ID

@app.command("/play")
def play_music(ack, respond, command):
    ack()
    query = command['text']
    video_url = f"https://www.youtube.com/results?search_query={query}"

    try:
        info = youtube_dl.YoutubeDL({'format': 'bestaudio'}).extract_info(video_url, download=False)
        audio_url = info['url']

        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as temp_audio:
            temp_audio.close()
            subprocess.run(["youtube-dl", "-x", "--audio-format", "mp3", "-o", temp_audio.name, audio_url])

            respond({
                "response_type": "in_channel",
                "text": f"Now playing: {info['title']}",
                "attachments": [
                    {
                        "text": f"<{audio_url}|Listen here>"
                    }
                ]
            })

    except Exception as e:
        respond(f"Failed to play music: {str(e)}")

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)

```

### 6. Package and Deploy the Lambda Function

Create a `requirements.txt` file in the `lambda` directory to specify the dependencies:

```plaintext
slack-bolt
youtube-dl
```

1. Install the dependencies and create a deployment package:

```sh
pip install -r requirements.txt -t .
zip -r9 ../lambda.zip .
```

2. Create the Lambda function using the AWS CLI:

```sh
aws lambda create-function --function-name MusicLambda \
--zip-file fileb://music_lambda.zip --handler lambda_function.lambda_handler --runtime python3.8 \
--role arn:aws:iam::<YOUR_ACCOUNT_ID>:role/MusicLambdaRole --region us-west-2
```

Replace `<YOUR_ACCOUNT_ID>` with your actual AWS account ID.

<!-- ### Step 5: Use a Virtual Environment and Package the Lambda Function

1. **Create a Virtual Environment**:

```sh
python3 -m venv venv
```

2. **Activate the Virtual Environment**:

```sh
source venv/bin/activate  # On Windows, use .\venv\Scripts\activate
```

3. **Install Dependencies**:

```sh
pip install -r requirements.txt
```

4. **Package the Lambda Function**:

```sh
zip -r ../lambda.zip *
```

5. **Deactivate the Virtual Environment**:

```sh
deactivate
```

6. **Clean Up** (Optional):

```sh
rm -rf venv
``` -->

### Step 6: Terraform Configuration

1. **Go back to the root directory and create a `main.tf` file for your Terraform configuration**:

```hcl
provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_lambda_function" "slack_music_bot" {
  function_name = "slack_music_bot"
  handler       = "lambda_function.handler"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "${path.module}/lambda.zip"
  environment {
    variables = {
      SLACK_SIGNING_SECRET = var.slack_signing_secret
      SLACK_BOT_TOKEN      = var.slack_bot_token
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.slack_music_bot.function_name}"
  retention_in_days = 14
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "Slack Music Bot API"
  description = "API Gateway for the Slack Music Bot"
}

resource "aws_api_gateway_resource" "slack_command" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "slack"
}

resource "aws_api_gateway_method" "post_slack_command" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.slack_command.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.slack_command.id
  http_method             = aws_api_gateway_method.post_slack_command.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.slack_music_bot.arn}/invocations"
}

resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod"
  depends_on = [
    aws_api_gateway_integration.lambda
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_music_bot.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.api.id}/*/POST/slack"
}

```

2. **Create a `terraform.tfvars` file to provide values for these variables**:

```hcl
slack_signing_secret = "your_slack_signing_secret"
slack_bot_token      = "your_slack_bot_token"
```

### Step 8: Deploy with Terraform

1. **Initialize Terraform, plan, and apply the configuration**:

```sh
terraform init
terraform plan
terraform apply
```

### Step 9: Update the Slack Command with the API Gateway Endpoint

1. **After deploying, get the API Gateway endpoint URL from the Terraform output or AWS Console**.
2. **Go back to your Slack app settings, and under Slash Commands, update the Request URL with the API Gateway endpoint**:
   - **Command**: `/play`
   - **Request URL**: `https://your-api-gateway-endpoint/slack`
   - **Short Description**: `Plays music in the channel`
   - **Usage Hint**: `[song name or YouTube link]`
   - **Escape Channels, Users, and Links Sent to Your App**: Leave this enabled.

### Step 10: Finalize the Slack Command Setup

1. **Autocomplete Entry**:
   - **Command**: `/play`
   - **Short Description**: `Plays music in the channel`
   - **Usage Hint**: `[song name or YouTube link]`

### Step 11: Invite the Bot to the Slack Channel

1. **Invite the Bot to the Channel**:

   - In your Slack workspace, go to the channel where you want the bot to operate.
   - Type `/invite @your-bot-name` to invite the bot to the channel.

2. **Get the Channel ID**:
   - To find the channel ID, you can use the Slack API or the Slack web interface.
   - Using the Slack web interface: Open the channel in Slack, click on the channel name at the top to open the channel details, and you'll see the channel ID in the URL. It will look something like `C1234567890`.

### Step 12: I made an error in logic above, the lambda needs the slack Channel ID so below is the Updated the Lambda Function to Include the Channel ID

1. **Modify `lambda_function.py` to include the channel ID**:

```python
import os
import json
import youtube_dl
from slack_bolt import App
from slack_bolt.adapter.aws_lambda import SlackRequestHandler
import subprocess
import tempfile

app = App(signing_secret=os.environ.get("SLACK_SIGNING_SECRET"))

channel_id = "your-channel-id"  # Replace with your actual channel ID

@app.command("/play")
def play_music(ack, respond, command):
    ack()
    query = command['text']
    video_url = f"https://www.youtube.com/results?search_query={query}"

    try:
        info = youtube_dl.YoutubeDL({'format': 'bestaudio'}).extract_info(video_url, download=False)
        audio_url = info['url']

        with tempfile.NamedTemporaryFile(delete=False, suffix=".mp3") as temp_audio:
            temp_audio.close()
            subprocess.run(["youtube-dl", "-x", "--audio-format", "mp3", "-o", temp_audio.name, audio_url])

            respond({
                "response_type": "in_channel",
                "text": f"Now playing: {info['title']}",
                "attachments": [
                    {
                        "text": f"<{audio_url}|Listen here>"
                    }
                ]
            })

    except Exception as e:
        respond(f"Failed to play music: {str(e)}")

def handler(event, context):
    slack_handler = SlackRequestHandler(app=app)
    return slack_handler.handle(event, context)
```

---
