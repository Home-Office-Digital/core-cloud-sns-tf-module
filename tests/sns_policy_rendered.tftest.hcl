// A real (non-mocked) AWS provider renders the aws_iam_policy_document data
// source locally, with no API calls, so these assertions inspect the actual
// rendered policy JSON (principals, action, resource) rather than a mocked
// placeholder. Credential and account checks are skipped so the plan runs
// offline in CI. This is the test that catches regressions dropping or altering
// the publish principals, which the mocked policy tests cannot.
provider "aws" {
  region                      = "eu-west-2"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

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

# The rendered publish policy grants SNS:Publish to the exact account ids and
# principal ARNs supplied, and targets the topic ARN.
run "rendered_publish_policy_contents" {
  command = plan

  # Give the account/region/partition metadata static values so the plan does
  # not call STS. aws_iam_policy_document is left to render through the real
  # provider so the assertions can inspect the actual policy JSON.
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "444455556666"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "eu-west-2"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  variables {
    topics = {
      shared = {
        name                        = "test-shared"
        allowed_publish_account_ids = ["222222222222"]
        allowed_publish_principals  = ["arn:aws:iam::333333333333:role/publisher"]
      }
    }
  }

  # Action is SNS:Publish.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.publish["shared"].json, "SNS:Publish")
    error_message = "Rendered publish policy must grant SNS:Publish"
  }

  # Both the account id and the principal ARN appear as principals.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.publish["shared"].json, "222222222222")
    error_message = "Rendered publish policy must include the allowed account id"
  }

  assert {
    condition     = strcontains(data.aws_iam_policy_document.publish["shared"].json, "arn:aws:iam::333333333333:role/publisher")
    error_message = "Rendered publish policy must include the allowed principal ARN"
  }

  # The resource is the topic ARN.
  assert {
    condition     = strcontains(data.aws_iam_policy_document.publish["shared"].json, ":sns:")
    error_message = "Rendered publish policy must target the topic ARN"
  }

  # The policy must not grant to a wildcard principal.
  assert {
    condition     = !strcontains(data.aws_iam_policy_document.publish["shared"].json, "\"AWS\":\"*\"")
    error_message = "Rendered publish policy must not grant to a wildcard principal"
  }
}
