// Mock provider to avoid real AWS calls during tests.
mock_provider "aws" {}

variables {
  // Required organization tags.
  tags = {
    cost-centre      = "CC1001"
    account-code     = "AC2002"
    portfolio-id     = "PF3003"
    project-id       = "PR4004"
    service-id       = "SV5005"
    environment-type = "nonprod"
    owner-business   = "platform"
    budget-holder    = "finops"
    source-repo      = "Home-Office-Digital/core-cloud-sns-tf-module"
    hosting-platform = "test-platform"
  }

  topics = {}
}

# Outputs expose an entry per topic and per subscription.
run "outputs_per_topic_and_subscription" {
  command = plan

  variables {
    topics = {
      events = {
        name = "test-events"
        subscriptions = {
          queue = {
            protocol = "sqs"
            endpoint = "arn:aws:sqs:eu-west-2:111111111111:test-queue"
          }
        }
      }
    }
  }

  assert {
    condition     = contains(keys(output.topic_arns), "events")
    error_message = "topic_arns output must contain an entry per topic"
  }

  assert {
    condition     = contains(keys(output.topic_names), "events")
    error_message = "topic_names output must contain an entry per topic"
  }

  assert {
    condition     = output.topic_names["events"] == "test-events"
    error_message = "topic_names output must expose the configured topic name"
  }

  assert {
    condition     = contains(keys(output.subscription_arns), "events")
    error_message = "subscription_arns output must have a top-level entry per topic"
  }

  assert {
    condition     = contains(keys(output.subscription_arns["events"]), "queue")
    error_message = "subscription_arns[topic] must contain an entry per subscription key"
  }
}
