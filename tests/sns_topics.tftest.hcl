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

# A standard topic is encrypted with the AWS-managed SNS key by default.
run "standard_topic_default_encryption" {
  command = plan

  variables {
    topics = {
      events = {
        name = "test-events"
      }
    }
  }

  assert {
    condition     = aws_sns_topic.this["events"].fifo_topic == false
    error_message = "A topic without fifo_topic set must default to a standard topic"
  }

  assert {
    condition     = aws_sns_topic.this["events"].kms_master_key_id == "alias/aws/sns"
    error_message = "A standard topic must default to the AWS-managed SNS key for encryption"
  }

  assert {
    condition     = aws_sns_topic.this["events"].name == "test-events"
    error_message = "Topic name must match the configured name"
  }
}

# cc_tags is mapped to the hyphenated resource-tag keys via common_tags, and the
# per-topic Name tag is added. This guards the public tagging contract against a
# typo or omitted mapping in local.common_tags.
run "cc_tags_mapped_to_resource_tags" {
  command = plan

  variables {
    topics = {
      events = {
        name = "test-events"
      }
    }
  }

  assert {
    condition = alltrue([
      aws_sns_topic.this["events"].tags["cost-centre"] == "CC1001",
      aws_sns_topic.this["events"].tags["account-code"] == "AC2002",
      aws_sns_topic.this["events"].tags["portfolio-id"] == "PF3003",
      aws_sns_topic.this["events"].tags["project-id"] == "PR4004",
      aws_sns_topic.this["events"].tags["service-id"] == "SV5005",
      aws_sns_topic.this["events"].tags["environment-type"] == "nonprod",
      aws_sns_topic.this["events"].tags["owner-business"] == "platform",
      aws_sns_topic.this["events"].tags["budget-holder"] == "finops",
    ])
    error_message = "cc_tags must map to all eight hyphenated resource-tag keys"
  }

  assert {
    condition     = aws_sns_topic.this["events"].tags["Name"] == "test-events"
    error_message = "The per-topic Name tag must be set to the topic name"
  }

  # The dropped estate keys must not leak back in.
  assert {
    condition = alltrue([
      !contains(keys(aws_sns_topic.this["events"].tags), "source-repo"),
      !contains(keys(aws_sns_topic.this["events"].tags), "hosting-platform"),
    ])
    error_message = "source-repo and hosting-platform are not part of the 8-key cc_tags contract"
  }
}

# A customer-managed key overrides the module default.
run "topic_custom_kms_key" {
  command = plan

  variables {
    topics = {
      secure = {
        name              = "test-secure"
        kms_master_key_id = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
      }
    }
  }

  assert {
    condition     = aws_sns_topic.this["secure"].kms_master_key_id == "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
    error_message = "A per-topic kms_master_key_id must override the module default"
  }
}

# An explicit empty string disables encryption for that topic.
run "topic_encryption_disabled" {
  command = plan

  variables {
    topics = {
      plain = {
        name              = "test-plain"
        kms_master_key_id = ""
      }
    }
  }

  assert {
    condition     = aws_sns_topic.this["plain"].kms_master_key_id == null
    error_message = "An empty kms_master_key_id must disable encryption (null) for that topic"
  }
}

# A FIFO topic sets fifo_topic and keeps its .fifo name.
run "fifo_topic_defaults" {
  command = plan

  variables {
    topics = {
      orders = {
        name                        = "test-orders.fifo"
        fifo_topic                  = true
        content_based_deduplication = true
        fifo_throughput_scope       = "MessageGroup"
      }
    }
  }

  assert {
    condition     = aws_sns_topic.this["orders"].fifo_topic == true
    error_message = "fifo_topic must be true for a FIFO topic"
  }

  assert {
    condition     = aws_sns_topic.this["orders"].name == "test-orders.fifo"
    error_message = "A FIFO topic name must retain its .fifo suffix"
  }

  assert {
    condition     = aws_sns_topic.this["orders"].content_based_deduplication == true
    error_message = "content_based_deduplication must be set on the FIFO topic"
  }

  assert {
    condition     = aws_sns_topic.this["orders"].fifo_throughput_scope == "MessageGroup"
    error_message = "fifo_throughput_scope must be wired onto the FIFO topic"
  }
}

# A FIFO topic without the .fifo suffix is rejected by the variable validation.
run "fifo_topic_invalid_name_rejected" {
  command = plan

  variables {
    topics = {
      bad = {
        name       = "test-bad"
        fifo_topic = true
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# A standard topic ending in .fifo is rejected by the variable validation.
run "standard_topic_with_fifo_suffix_rejected" {
  command = plan

  variables {
    topics = {
      bad = {
        name = "test-bad.fifo"
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# Two topics with the same name are rejected: they would target one SNS topic.
run "duplicate_topic_names_rejected" {
  command = plan

  variables {
    topics = {
      a = { name = "test-dupe" }
      b = { name = "test-dupe" }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# A FIFO topic with a standard (non-.fifo) SQS endpoint is rejected, because a
# standard queue would not preserve the FIFO topic's ordering guarantees.
run "fifo_topic_standard_sqs_endpoint_rejected" {
  command = plan

  variables {
    topics = {
      orders = {
        name       = "test-orders.fifo"
        fifo_topic = true
        subscriptions = {
          queue = {
            protocol = "sqs"
            endpoint = "arn:aws:sqs:eu-west-2:111111111111:test-standard-queue"
          }
        }
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# A FIFO topic with a FIFO SQS endpoint is accepted.
run "fifo_topic_fifo_sqs_endpoint_accepted" {
  command = plan

  variables {
    topics = {
      orders = {
        name       = "test-orders.fifo"
        fifo_topic = true
        subscriptions = {
          queue = {
            protocol = "sqs"
            endpoint = "arn:aws:sqs:eu-west-2:111111111111:test-queue.fifo"
          }
        }
      }
    }
  }

  assert {
    condition     = aws_sns_topic_subscription.this[jsonencode(["orders", "queue"])].protocol == "sqs"
    error_message = "A FIFO topic must accept a FIFO SQS queue subscription"
  }
}
