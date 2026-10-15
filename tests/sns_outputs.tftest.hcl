// Mock provider to avoid real AWS calls during tests.
mock_provider "aws" {}

variables {
  // Required organization tags.
  cc_tags = {
    cost_centre      = "CC1001"
    account_code     = "AC2002"
    portfolio_id     = "PF3003"
    project_id       = "PR4004"
    service_id       = "SV5005"
    environment_type = "nonprod"
    owner_business   = "platform"
    budget_holder    = "finops"
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
