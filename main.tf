data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

# Module-generated topic access policy. One document per topic that requests
# one (see local.generated_policy_topics).
#
# The cross-account publish statement grants SNS:Publish on the topic ARN to the
# union of allowed_publish_account_ids and allowed_publish_principals, listed
# directly as AWS principals. A bare account id grants the whole account (AWS
# expands it to the account root), and a role or user ARN grants that principal.
# This is the form AWS itself generates for AddPermission, and it works for
# ordinary cross-account IAM requests, unlike a Principal "*" scoped by an
# aws:SourceOwner condition. The statement is only emitted when there are
# principals to grant, so a topic that supplies only extra_policy_documents does
# not render an invalid empty-principals statement.
#
# extra_policy_documents are merged in via source_policy_documents, letting
# callers add statements onto the generated policy without hand-writing the
# whole thing. source_policy_documents requires unique Sids, so caller
# statements must not reuse "AllowCrossAccountPublish".
data "aws_iam_policy_document" "publish" {
  for_each = local.generated_policy_topics

  source_policy_documents = each.value.extra_policy_documents

  dynamic "statement" {
    for_each = length(local.publish_principals[each.key]) > 0 ? [1] : []
    content {
      sid    = "AllowCrossAccountPublish"
      effect = "Allow"

      actions   = ["SNS:Publish"]
      resources = [local.topic_arns[each.key]]

      principals {
        type        = "AWS"
        identifiers = local.publish_principals[each.key]
      }
    }
  }
}

resource "aws_sns_topic" "this" {
  for_each = var.topics

  name         = each.value.name
  display_name = each.value.display_name

  # FIFO configuration. fifo_throughput_scope and content_based_deduplication
  # only apply to FIFO topics.
  fifo_topic                  = each.value.fifo_topic
  content_based_deduplication = each.value.fifo_topic ? each.value.content_based_deduplication : null
  fifo_throughput_scope       = each.value.fifo_topic ? each.value.fifo_throughput_scope : null
  archive_policy              = each.value.fifo_topic ? each.value.archive_policy : null

  # Server-side encryption. Resolved in locals: per-topic override, else the
  # module default (AWS-managed SNS key), else null when explicitly disabled.
  kms_master_key_id = local.topic_kms_master_key_id[each.key]

  # Access policy. Resolved in locals: a raw per-topic policy takes precedence
  # over the module-generated cross-account publish policy; null when neither is
  # set so SNS applies its default policy.
  policy = local.topic_policy[each.key]

  delivery_policy   = each.value.delivery_policy
  signature_version = each.value.signature_version
  tracing_config    = each.value.tracing_config

  # Delivery status logging. Role ARNs are supplied by the caller and always
  # honoured; sample rates are percentages (0-100).
  sqs_success_feedback_role_arn    = each.value.sqs_success_feedback_role_arn
  sqs_failure_feedback_role_arn    = each.value.sqs_failure_feedback_role_arn
  sqs_success_feedback_sample_rate = each.value.sqs_success_feedback_sample_rate

  lambda_success_feedback_role_arn    = each.value.lambda_success_feedback_role_arn
  lambda_failure_feedback_role_arn    = each.value.lambda_failure_feedback_role_arn
  lambda_success_feedback_sample_rate = each.value.lambda_success_feedback_sample_rate

  http_success_feedback_role_arn    = each.value.http_success_feedback_role_arn
  http_failure_feedback_role_arn    = each.value.http_failure_feedback_role_arn
  http_success_feedback_sample_rate = each.value.http_success_feedback_sample_rate

  firehose_success_feedback_role_arn    = each.value.firehose_success_feedback_role_arn
  firehose_failure_feedback_role_arn    = each.value.firehose_failure_feedback_role_arn
  firehose_success_feedback_sample_rate = each.value.firehose_success_feedback_sample_rate

  application_success_feedback_role_arn    = each.value.application_success_feedback_role_arn
  application_failure_feedback_role_arn    = each.value.application_failure_feedback_role_arn
  application_success_feedback_sample_rate = each.value.application_success_feedback_sample_rate

  tags = merge(var.tags, {
    Name = each.value.name
  })
}

# Optional data protection policy per topic. Scans message payloads for
# sensitive data (for example PII). Standard topics only; the variable
# validation rejects it on FIFO topics.
resource "aws_sns_topic_data_protection_policy" "this" {
  for_each = local.data_protection_topics

  arn    = aws_sns_topic.this[each.key].arn
  policy = each.value.data_protection_policy
}

resource "aws_sns_topic_subscription" "this" {
  for_each = local.topic_subscriptions

  topic_arn = aws_sns_topic.this[each.value.topic_key].arn
  protocol  = each.value.sub.protocol
  endpoint  = each.value.sub.endpoint

  raw_message_delivery            = each.value.sub.raw_message_delivery
  filter_policy                   = each.value.sub.filter_policy
  filter_policy_scope             = each.value.sub.filter_policy_scope
  redrive_policy                  = each.value.sub.redrive_policy
  delivery_policy                 = each.value.sub.delivery_policy
  replay_policy                   = each.value.sub.replay_policy
  subscription_role_arn           = each.value.sub.subscription_role_arn
  confirmation_timeout_in_minutes = each.value.sub.confirmation_timeout_in_minutes
  endpoint_auto_confirms          = each.value.sub.endpoint_auto_confirms

  lifecycle {
    # SNS FIFO topics deliver to Amazon SQS only. Lambda, Firehose, email,
    # email-json, SMS, HTTP(S) and application are not supported as direct
    # subscribers to a FIFO topic (Lambda/Firehose fan-out from FIFO requires an
    # intermediate SQS queue). Restrict FIFO subscriptions to sqs so an
    # unsupported protocol fails at plan rather than at apply.
    precondition {
      condition     = !var.topics[each.value.topic_key].fifo_topic || each.value.sub.protocol == "sqs"
      error_message = "FIFO topic \"${var.topics[each.value.topic_key].name}\" cannot have a \"${each.value.sub.protocol}\" subscription. SNS FIFO topics support only sqs subscriptions; use an SQS queue to fan out to Lambda or Firehose."
    }
  }
}
