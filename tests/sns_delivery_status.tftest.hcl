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

# SQS delivery status feedback roles and sample rate land on the topic.
run "sqs_delivery_status_wired" {
  command = plan

  variables {
    topics = {
      logged = {
        name                             = "test-logged"
        sqs_success_feedback_role_arn    = "arn:aws:iam::111111111111:role/sns-success"
        sqs_failure_feedback_role_arn    = "arn:aws:iam::111111111111:role/sns-failure"
        sqs_success_feedback_sample_rate = 100
      }
    }
  }

  assert {
    condition     = aws_sns_topic.this["logged"].sqs_success_feedback_role_arn == "arn:aws:iam::111111111111:role/sns-success"
    error_message = "sqs_success_feedback_role_arn must be wired onto the topic"
  }

  assert {
    condition     = aws_sns_topic.this["logged"].sqs_failure_feedback_role_arn == "arn:aws:iam::111111111111:role/sns-failure"
    error_message = "sqs_failure_feedback_role_arn must be wired onto the topic"
  }

  assert {
    condition     = aws_sns_topic.this["logged"].sqs_success_feedback_sample_rate == 100
    error_message = "sqs_success_feedback_sample_rate must be wired onto the topic"
  }
}

# Lambda delivery status feedback roles land on the topic.
run "lambda_delivery_status_wired" {
  command = plan

  variables {
    topics = {
      logged = {
        name                                = "test-logged"
        lambda_success_feedback_role_arn    = "arn:aws:iam::111111111111:role/sns-lambda-success"
        lambda_success_feedback_sample_rate = 50
      }
    }
  }

  assert {
    condition     = aws_sns_topic.this["logged"].lambda_success_feedback_role_arn == "arn:aws:iam::111111111111:role/sns-lambda-success"
    error_message = "lambda_success_feedback_role_arn must be wired onto the topic"
  }

  assert {
    condition     = aws_sns_topic.this["logged"].lambda_success_feedback_sample_rate == 50
    error_message = "lambda_success_feedback_sample_rate must be wired onto the topic"
  }
}

# When no delivery status inputs are given, the attributes are unset on the topic.
run "no_delivery_status_defaults_null" {
  command = plan

  variables {
    topics = {
      plain = {
        name = "test-plain"
      }
    }
  }

  assert {
    condition     = aws_sns_topic.this["plain"].sqs_success_feedback_role_arn == null
    error_message = "sqs_success_feedback_role_arn must be unset when not provided"
  }

  assert {
    condition     = aws_sns_topic.this["plain"].lambda_failure_feedback_role_arn == null
    error_message = "lambda_failure_feedback_role_arn must be unset when not provided"
  }
}

# A sample rate above 100 is rejected by the variable validation.
run "sample_rate_above_100_rejected" {
  command = plan

  variables {
    topics = {
      bad = {
        name                             = "test-bad"
        sqs_success_feedback_sample_rate = 101
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}
