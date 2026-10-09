locals {
  # Effective KMS key per topic. A per-topic kms_master_key_id takes precedence
  # over the module default. An explicit empty string disables encryption for
  # that topic (the resource receives null). When the attribute is unset (null)
  # the module default applies, which defaults to the AWS-managed SNS key.
  topic_kms_master_key_id = {
    for key, topic in var.topics : key => (
      topic.kms_master_key_id == null
      ? var.default_kms_master_key_id
      : (trimspace(topic.kms_master_key_id) == "" ? null : topic.kms_master_key_id)
    )
  }

  # Predicted topic ARNs. The cross-account publish policy document references
  # the topic ARN, and the topic references the policy, so the ARN is built from
  # account/partition/region rather than from the resource to avoid a cycle.
  topic_arns = {
    for key, topic in var.topics : key =>
    "arn:${data.aws_partition.current.partition}:sns:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${topic.name}"
  }

  # Whether a topic supplies a raw policy that must be used verbatim.
  topic_has_raw_policy = {
    for key, topic in var.topics : key =>
    topic.policy != null && trimspace(coalesce(topic.policy, "")) != ""
  }

  # Topics that get a module-generated cross-account publish policy: those with
  # at least one allowed publish account id or principal and no raw override.
  generated_policy_topics = {
    for key, topic in var.topics : key => topic
    if !local.topic_has_raw_policy[key] && (
      length(topic.allowed_publish_account_ids) > 0 || length(topic.allowed_publish_principals) > 0
    )
  }

  # Principals allowed to publish, per topic: the union of the allowed account
  # ids and the explicit principal ARNs, listed directly as AWS principals.
  publish_principals = {
    for key, topic in local.generated_policy_topics : key => distinct(concat(
      topic.allowed_publish_account_ids,
      topic.allowed_publish_principals,
    ))
  }

  # Effective topic access policy. A raw per-topic policy takes precedence over
  # the module-generated cross-account publish policy. When neither is set the
  # value is null so SNS applies its default policy.
  topic_policy = {
    for key, topic in var.topics : key => (
      local.topic_has_raw_policy[key]
      ? topic.policy
      : try(data.aws_iam_policy_document.publish[key].json, null)
    )
  }

  # Flatten the per-topic subscriptions maps into a single map so
  # aws_sns_topic_subscription can be driven with for_each (never count).
  #
  # The key is jsonencode([topic_key, sub_key]) rather than a "-" join. A join
  # is not injective: ("orders", "queue-fast") and ("orders-queue", "fast")
  # would both produce "orders-queue-fast" and one subscription would be lost in
  # the merge. Encoding the pair as a JSON array keeps the key unique for any
  # topic and subscription key, including keys that themselves contain hyphens.
  topic_subscriptions = merge([
    for topic_key, topic in var.topics : {
      for sub_key, sub in topic.subscriptions :
      jsonencode([topic_key, sub_key]) => {
        topic_key = topic_key
        sub       = sub
      }
    }
  ]...)
}
