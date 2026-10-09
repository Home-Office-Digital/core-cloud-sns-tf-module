// Mock provider to avoid real AWS calls during tests.
mock_provider "aws" {}

variables {
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

# A data protection policy is wired onto the topic when supplied.
run "data_protection_policy_wired" {
  command = plan

  variables {
    topics = {
      events = {
        name                   = "test-events"
        data_protection_policy = "{\"Name\":\"__example\",\"Version\":\"2021-06-01\",\"Statement\":[{\"Sid\":\"deny-email\",\"DataDirection\":\"Inbound\",\"DataIdentifier\":[\"arn:aws:dataprotection::aws:data-identifier/EmailAddress\"],\"Operation\":{\"Deny\":{}},\"Principal\":[\"*\"]}]}"
      }
    }
  }

  assert {
    condition     = contains(keys(aws_sns_topic_data_protection_policy.this), "events")
    error_message = "A data protection policy resource must be created for a topic that sets data_protection_policy"
  }

  assert {
    condition     = aws_sns_topic_data_protection_policy.this["events"].policy == "{\"Name\":\"__example\",\"Version\":\"2021-06-01\",\"Statement\":[{\"Sid\":\"deny-email\",\"DataDirection\":\"Inbound\",\"DataIdentifier\":[\"arn:aws:dataprotection::aws:data-identifier/EmailAddress\"],\"Operation\":{\"Deny\":{}},\"Principal\":[\"*\"]}]}"
    error_message = "The data protection policy must be passed through verbatim"
  }
}

# A topic without a data protection policy creates no such resource.
run "no_data_protection_policy_by_default" {
  command = plan

  variables {
    topics = {
      plain = {
        name = "test-plain"
      }
    }
  }

  assert {
    condition     = !contains(keys(aws_sns_topic_data_protection_policy.this), "plain")
    error_message = "No data protection policy resource should be created when the input is unset"
  }
}

# A data protection policy on a FIFO topic is rejected (standard topics only).
run "data_protection_policy_on_fifo_rejected" {
  command = plan

  variables {
    topics = {
      orders = {
        name                   = "test-orders.fifo"
        fifo_topic             = true
        data_protection_policy = "{\"Name\":\"__example\",\"Version\":\"2021-06-01\",\"Statement\":[]}"
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}
