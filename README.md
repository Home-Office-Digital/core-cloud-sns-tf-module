# core-cloud-sns-tf-module

A Core Cloud Terraform module for provisioning [Amazon SNS](https://docs.aws.amazon.com/sns/latest/dg/welcome.html) topics. It supports standard and FIFO topics, server-side encryption with KMS, nested subscriptions (SQS, Lambda, email and others), cross-account publish topic policies, and per-protocol delivery status logging.

## Overview

The module takes a `topics` map of typed objects and, for each entry, creates:

- An `aws_sns_topic` (standard or FIFO), encrypted at rest by default.
- One `aws_sns_topic_subscription` per entry in that topic's `subscriptions` map, created with `for_each`.
- A cross-account publish policy, generated from convenience inputs or supplied verbatim.

Key design choices:

- **Encrypted by default.** Each topic is encrypted with the AWS-managed SNS key (`alias/aws/sns`) unless you supply a customer-managed key via `kms_master_key_id`, or opt out per topic by setting `kms_master_key_id = ""`.
- **`for_each`, not `count`.** Both topics and subscriptions are keyed maps, so adding or removing one does not churn unrelated resources.
- **Policy escape hatch.** Convenience inputs (`allowed_publish_account_ids`, `allowed_publish_principals`) generate a cross-account publish policy. Supplying a raw `policy` JSON overrides the generated document entirely.
- **FIFO safety.** FIFO topic names are validated to end in `.fifo`. SNS FIFO topics deliver to Amazon SQS only, so the module rejects every other direct subscription protocol — email, email-json, SMS, HTTP(S), application, and also Lambda and Firehose. To fan out a FIFO topic to Lambda or Firehose, subscribe an SQS (FIFO) queue and trigger the downstream service from that queue. An `sqs` subscription on a FIFO topic must also point at a FIFO queue (endpoint ending in `.fifo`).

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.7.5 |
| aws | >= 6.66.0 |

## Usage

```hcl
module "sns" {
  source = "git::https://github.com/Home-Office-Digital/core-cloud-sns-tf-module.git?ref=v0.1.0"

  topics = {
    events = {
      name = "core-cloud-events"

      # Cross-account publishing to an encrypted topic needs a customer-managed
      # KMS key whose key policy grants the publishing account kms:GenerateDataKey*
      # and kms:Decrypt. The AWS-managed alias/aws/sns key cannot do this.
      kms_master_key_id           = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
      allowed_publish_account_ids = ["222222222222"]

      subscriptions = {
        queue = {
          protocol             = "sqs"
          endpoint             = "arn:aws:sqs:eu-west-2:111111111111:events-queue"
          raw_message_delivery = true
        }
      }
    }

    orders = {
      name                        = "core-cloud-orders.fifo"
      fifo_topic                  = true
      content_based_deduplication = true
    }
  }

  tags = {
    cost-centre      = "CC1001"
    account-code     = "AC2002"
    portfolio-id     = "cto"
    project-id       = "core-cloud"
    service-id       = "sns"
    environment-type = "nonprod"
    owner-business   = "core-cloud"
    budget-holder    = "core-cloud"
    source-repo      = "Home-Office-Digital/core-cloud-sns-tf-module"
    hosting-platform = "aws"
  }
}
```

## Topics input

Each entry in `var.topics` is an object with the following attributes.

### Naming and identity

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | string | — | Topic name. For a FIFO topic it must end in `.fifo`; for a standard topic it must not. |
| `display_name` | string | `null` | Display name used for SMS messages. |

### FIFO

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `fifo_topic` | bool | `false` | Create a FIFO topic. |
| `content_based_deduplication` | bool | `false` | Enable content-based deduplication (FIFO only). |
| `fifo_throughput_scope` | string | `null` | `Topic` or `MessageGroup` for high-throughput FIFO. |
| `archive_policy` | string | `null` | Message archive policy JSON (FIFO only). |

### Encryption

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `kms_master_key_id` | string | `null` | KMS key ARN or alias. When `null`, the module default (`alias/aws/sns`) applies. Set to `""` to disable encryption for this topic. For cross-account publishing see the note below. |

> **Cross-account publishing and encryption.** The default key, the AWS-managed `alias/aws/sns`, cannot have its key policy edited, so an external account cannot be granted the `kms:GenerateDataKey*`/`kms:Decrypt` it needs to publish to an encrypted topic. To allow cross-account publishing to an encrypted topic, supply a customer-managed KMS key via `kms_master_key_id` and grant the publishing account `kms:GenerateDataKey*` and `kms:Decrypt` in that key's policy. Alternatively set `kms_master_key_id = ""` to leave the topic unencrypted (not recommended for sensitive data).

### Delivery, signing and tracing

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `delivery_policy` | string | `null` | SNS delivery policy JSON (HTTP/S retries, backoff). |
| `signature_version` | number | `null` | `1` (SHA1) or `2` (SHA256). |
| `tracing_config` | string | `null` | `PassThrough` or `Active` (X-Ray). Active tracing is [supported on both standard and FIFO topics](https://docs.aws.amazon.com/sns/latest/dg/sns-active-tracing.html). |
| `data_protection_policy` | string | `null` | Data protection policy JSON. Scans message payloads for sensitive data such as PII. Standard topics only (rejected on FIFO topics). AWS no longer offers SNS message data protection to new customers as of 30 April 2026; it remains available only in accounts that configured a policy before that date. See [AWS's availability notice](https://docs.aws.amazon.com/sns/latest/dg/sns-message-data-protection-availability-change.html). |

### Access policy

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `policy` | string | `null` | Raw topic policy JSON. Full-replacement escape hatch: overrides the generated policy entirely. |
| `allowed_publish_account_ids` | list(string) | `[]` | Account IDs permitted to publish. Each is listed directly as an `AWS` principal, granting the whole account. |
| `allowed_publish_principals` | list(string) | `[]` | Principal ARNs (roles/users) permitted to publish, listed directly as `AWS` principals. |
| `extra_policy_documents` | list(string) | `[]` | Additional IAM policy document JSON strings merged into the generated policy. Lets you add statements without hand-writing the whole policy. Each statement must use a `Sid` other than `AllowCrossAccountPublish`. |

When `allowed_publish_account_ids` and/or `allowed_publish_principals` are set (and no raw `policy` is given), the module generates one `Allow SNS:Publish` statement whose principals are the union of both lists. Account IDs grant the whole account; ARNs grant that specific role or user. This is the form AWS itself uses, and it works for ordinary cross-account IAM publish requests.

To add statements to the generated policy without replacing it, pass `extra_policy_documents` (a list of IAM policy document JSON strings). They are merged in via the `aws_iam_policy_document` `source_policy_documents` argument, so the generated publish statement is preserved and your statements are appended. The merge requires unique `Sid`s. Supplying only `extra_policy_documents` (no publish principals) generates a policy containing just those statements. The raw `policy` input remains the full-replacement escape hatch.

### Delivery status logging

Per protocol (`sqs`, `lambda`, `http`, `firehose`, `application`): supply the CloudWatch Logs IAM role ARNs. The sample rate is a percentage (0–100) of successfully delivered messages.

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `<protocol>_success_feedback_role_arn` | string | `null` | IAM role to log successful deliveries. |
| `<protocol>_failure_feedback_role_arn` | string | `null` | IAM role to log failed deliveries. |
| `<protocol>_success_feedback_sample_rate` | number | `null` | Percentage (0–100) of successes to sample. |

### Subscriptions

Each entry in a topic's `subscriptions` map is an object:

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `protocol` | string | — | `sqs`, `lambda`, `email`, `email-json`, `http`, `https`, `sms`, `firehose` or `application`. |
| `endpoint` | string | — | Endpoint matching the protocol (ARN, URL, email, phone). |
| `raw_message_delivery` | bool | `null` | Pass the original message without SNS JSON wrapping. |
| `filter_policy` | string | `null` | Subscription filter policy JSON. |
| `filter_policy_scope` | string | `null` | `MessageAttributes` or `MessageBody`. |
| `redrive_policy` | string | `null` | Dead-letter queue redrive policy JSON. |
| `delivery_policy` | string | `null` | Per-subscription delivery policy JSON (HTTP/S). |
| `replay_policy` | string | `null` | Archived message replay policy JSON. |
| `subscription_role_arn` | string | `null` | Required when `protocol` is `firehose`. |
| `confirmation_timeout_in_minutes` | number | `null` | Minutes to wait for subscription confirmation (HTTP/S). |
| `endpoint_auto_confirms` | bool | `null` | Whether the endpoint can auto-confirm. |

> **The module creates the subscription, not the target's permission to receive.** A subscription only delivers if the target resource allows SNS to send to it. The caller is responsible for granting that access:
> - **SQS**: the queue policy must allow `sqs:SendMessage` from `sns.amazonaws.com`, scoped to the topic ARN via `aws:SourceArn`.
> - **Lambda**: an `aws_lambda_permission` must allow `lambda:InvokeFunction` with principal `sns.amazonaws.com` and the topic ARN as `source_arn`.
>
> A successful `apply` creates the subscription but does not prove delivery works; verify the target permission separately.

> **Pending confirmation for `email`, `email-json`, and non-auto-confirming `http`/`https`.** These subscriptions stay in a pending state until confirmed outside Terraform (for example by clicking the link in the confirmation email). While pending, AWS will not let Terraform unsubscribe them: a `destroy` removes the subscription from Terraform state but leaves the pending subscription in AWS. `sqs`, `lambda` and `firehose` confirm automatically and are not affected.

## Module inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `topics` | map(object) | — | Map of topic configurations keyed by an arbitrary topic key. |
| `default_kms_master_key_id` | string | `"alias/aws/sns"` | Default KMS key used when a topic does not set `kms_master_key_id`. |
| `tags` | object | — | Mandatory Core Cloud tags applied to all resources. |

## Outputs

| Name | Description |
|------|-------------|
| `topic_arns` | Map of topic ARNs keyed by topic key. |
| `topic_ids` | Map of topic IDs (ARNs) keyed by topic key. |
| `topic_names` | Map of topic names keyed by topic key. |
| `topic_owners` | Map of owning account IDs keyed by topic key. |
| `data_protection_policy_topic_arns` | Map of topic ARNs that have a data protection policy, keyed by topic key. |
| `subscription_arns` | Nested map of subscription ARNs: topic key => subscription key => ARN. |

## Testing

Native Terraform tests run against a mocked AWS provider:

```sh
terraform test
```
