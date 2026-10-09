// Mock provider to avoid real AWS calls during tests. The aws_iam_policy_document
// json attribute is computed, so under a mock it would otherwise be a random
// string that fails the aws_sns_topic policy JSON validation. Provide a valid
// JSON default so the topic resource accepts it. Assertions that need to see
// the real rendered statements use a dedicated run that reads the data source
// directly (the data source itself is evaluated by the provider's own logic).
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowCrossAccountPublish\",\"Effect\":\"Allow\",\"Action\":\"SNS:Publish\"}]}"
    }
  }
}

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

# Convenience inputs generate a cross-account publish policy document for the
# topic, and that document is wired onto the topic's policy.
run "generated_cross_account_publish_policy" {
  command = plan

  variables {
    topics = {
      shared = {
        name                        = "test-shared"
        allowed_publish_account_ids = ["222222222222"]
      }
    }
  }

  # A policy document is generated for the topic.
  assert {
    condition     = contains(keys(data.aws_iam_policy_document.publish), "shared")
    error_message = "A generated publish policy document must exist for a topic with allowed_publish_account_ids"
  }

  # The topic's policy is the generated document (not null and not a raw policy).
  assert {
    condition     = aws_sns_topic.this["shared"].policy == data.aws_iam_policy_document.publish["shared"].json
    error_message = "The topic policy must be the generated cross-account publish document"
  }
}

# A topic configured with only principals still generates a policy document.
run "generated_policy_with_principals" {
  command = plan

  variables {
    topics = {
      shared = {
        name                       = "test-shared"
        allowed_publish_principals = ["arn:aws:iam::222222222222:root"]
      }
    }
  }

  assert {
    condition     = contains(keys(data.aws_iam_policy_document.publish), "shared")
    error_message = "A generated publish document must exist for a topic with allowed_publish_principals"
  }

  assert {
    condition     = aws_sns_topic.this["shared"].policy == data.aws_iam_policy_document.publish["shared"].json
    error_message = "The topic policy must be the generated document when principals are supplied"
  }
}

# A topic with both account IDs and explicit principals still generates a single
# publish document (the principals are the union of the two inputs).
run "generated_policy_with_accounts_and_principals" {
  command = plan

  variables {
    topics = {
      shared = {
        name                        = "test-shared"
        allowed_publish_account_ids = ["222222222222"]
        allowed_publish_principals  = ["arn:aws:iam::333333333333:role/publisher"]
      }
    }
  }

  assert {
    condition     = contains(keys(data.aws_iam_policy_document.publish), "shared")
    error_message = "A generated publish document must exist when both account ids and principals are set"
  }

  assert {
    condition     = aws_sns_topic.this["shared"].policy == data.aws_iam_policy_document.publish["shared"].json
    error_message = "The topic policy must be the generated document when both account ids and principals are set"
  }
}

# A raw policy overrides the generated document entirely.
run "raw_policy_override" {
  command = plan

  variables {
    topics = {
      shared = {
        name                        = "test-shared"
        allowed_publish_account_ids = ["222222222222"]
        policy                      = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Raw\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"SNS:Publish\",\"Resource\":\"*\"}]}"
      }
    }
  }

  # No generated document is produced when a raw policy is supplied.
  assert {
    condition     = !contains(keys(data.aws_iam_policy_document.publish), "shared")
    error_message = "No generated publish document should be produced when a raw policy is set"
  }

  # The topic uses the raw policy verbatim.
  assert {
    condition     = aws_sns_topic.this["shared"].policy == "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"Raw\",\"Effect\":\"Deny\",\"Principal\":\"*\",\"Action\":\"SNS:Publish\",\"Resource\":\"*\"}]}"
    error_message = "The raw policy must be used verbatim and override the generated document"
  }
}

# A wildcard publish principal is rejected: it would make the topic public.
run "wildcard_publish_principal_rejected" {
  command = plan

  variables {
    topics = {
      shared = {
        name                       = "test-shared"
        allowed_publish_principals = ["*"]
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# A blank publish principal is rejected.
run "blank_publish_principal_rejected" {
  command = plan

  variables {
    topics = {
      shared = {
        name                       = "test-shared"
        allowed_publish_principals = [""]
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# A non-12-digit publish account id is rejected.
run "invalid_publish_account_id_rejected" {
  command = plan

  variables {
    topics = {
      shared = {
        name                        = "test-shared"
        allowed_publish_account_ids = ["12345"]
      }
    }
  }

  expect_failures = [
    var.topics,
  ]
}

# A topic with neither convenience inputs nor a raw policy produces no generated
# policy document, so SNS applies its default policy.
run "no_policy_leaves_default" {
  command = plan

  variables {
    topics = {
      plain = {
        name = "test-plain"
      }
    }
  }

  assert {
    condition     = !contains(keys(data.aws_iam_policy_document.publish), "plain")
    error_message = "A topic with no publish inputs must not generate a publish policy document"
  }
}
