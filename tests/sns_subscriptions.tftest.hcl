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

# SQS and Lambda subscriptions are created and wired to their topic.
run "sqs_and_lambda_subscriptions" {
  command = plan

  variables {
    topics = {
      fanout = {
        name = "test-fanout"
        subscriptions = {
          queue = {
            protocol             = "sqs"
            endpoint             = "arn:aws:sqs:eu-west-2:111111111111:test-queue"
            raw_message_delivery = true
          }
          fn = {
            protocol = "lambda"
            endpoint = "arn:aws:lambda:eu-west-2:111111111111:function:test-fn"
          }
        }
      }
    }
  }

  # The SQS subscription uses the sqs protocol and the queue ARN endpoint.
  assert {
    condition     = aws_sns_topic_subscription.this[jsonencode(["fanout", "queue"])].protocol == "sqs"
    error_message = "The SQS subscription must use the sqs protocol"
  }

  assert {
    condition     = aws_sns_topic_subscription.this[jsonencode(["fanout", "queue"])].endpoint == "arn:aws:sqs:eu-west-2:111111111111:test-queue"
    error_message = "The SQS subscription endpoint must be the queue ARN"
  }

  assert {
    condition     = aws_sns_topic_subscription.this[jsonencode(["fanout", "queue"])].raw_message_delivery == true
    error_message = "raw_message_delivery must be wired onto the subscription"
  }

  # The Lambda subscription uses the lambda protocol.
  assert {
    condition     = aws_sns_topic_subscription.this[jsonencode(["fanout", "fn"])].protocol == "lambda"
    error_message = "The Lambda subscription must use the lambda protocol"
  }
}

# An email subscription on a standard topic is accepted.
run "email_subscription_on_standard_topic" {
  command = plan

  variables {
    topics = {
      alerts = {
        name = "test-alerts"
        subscriptions = {
          ops = {
            protocol = "email"
            endpoint = "ops@example.gov.uk"
          }
        }
      }
    }
  }

  assert {
    condition     = aws_sns_topic_subscription.this[jsonencode(["alerts", "ops"])].protocol == "email"
    error_message = "An email subscription on a standard topic must be accepted"
  }
}

# A firehose subscription carries its subscription_role_arn.
run "firehose_subscription_role" {
  command = plan

  variables {
    topics = {
      stream = {
        name = "test-stream"
        subscriptions = {
          fh = {
            protocol              = "firehose"
            endpoint              = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/test-stream"
            subscription_role_arn = "arn:aws:iam::111111111111:role/test-firehose"
          }
        }
      }
    }
  }

  assert {
    condition     = aws_sns_topic_subscription.this[jsonencode(["stream", "fh"])].subscription_role_arn == "arn:aws:iam::111111111111:role/test-firehose"
    error_message = "A firehose subscription must carry its subscription_role_arn"
  }
}

# A firehose subscription without a subscription_role_arn is rejected.
run "firehose_without_role_rejected" {
  command = plan

  variables {
    topics = {
      stream = {
        name = "test-stream"
        subscriptions = {
          fh = {
            protocol = "firehose"
            endpoint = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/test-stream"
          }
        }
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# An unsupported protocol is rejected by the variable validation.
run "invalid_protocol_rejected" {
  command = plan

  variables {
    topics = {
      bad = {
        name = "test-bad"
        subscriptions = {
          wrong = {
            protocol = "carrier-pigeon"
            endpoint = "nowhere"
          }
        }
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# An email subscription on a FIFO topic is rejected by the resource precondition.
run "email_on_fifo_topic_rejected" {
  command = plan

  variables {
    topics = {
      orders = {
        name       = "test-orders.fifo"
        fifo_topic = true
        subscriptions = {
          ops = {
            protocol = "email"
            endpoint = "ops@example.gov.uk"
          }
        }
      }
    }
  }

  expect_failures = [
    aws_sns_topic_subscription.this,
  ]
}

# A lambda subscription on a FIFO topic is rejected: SNS FIFO delivers to SQS
# only. Lambda is not a supported direct FIFO subscriber.
run "lambda_on_fifo_topic_rejected" {
  command = plan

  variables {
    topics = {
      orders = {
        name       = "test-orders.fifo"
        fifo_topic = true
        subscriptions = {
          fn = {
            protocol = "lambda"
            endpoint = "arn:aws:lambda:eu-west-2:111111111111:function:test-fn"
          }
        }
      }
    }
  }

  expect_failures = [
    aws_sns_topic_subscription.this,
  ]
}

# A firehose subscription on a FIFO topic is rejected for the same reason.
run "firehose_on_fifo_topic_rejected" {
  command = plan

  variables {
    topics = {
      orders = {
        name       = "test-orders.fifo"
        fifo_topic = true
        subscriptions = {
          fh = {
            protocol              = "firehose"
            endpoint              = "arn:aws:firehose:eu-west-2:111111111111:deliverystream/test-stream"
            subscription_role_arn = "arn:aws:iam::111111111111:role/test-firehose"
          }
        }
      }
    }
  }

  expect_failures = [
    aws_sns_topic_subscription.this,
  ]
}
