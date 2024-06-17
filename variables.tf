variable "slack_signing_secret" {
  description = "Slack signing secret"
  type        = string
}

variable "slack_bot_token" {
  description = "Slack bot token"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}
