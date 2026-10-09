variable "topics" {
  description = "A map of SNS topic configurations, keyed by an arbitrary topic key."
  type = map(object({
    # Naming / identity. For a FIFO topic, name must end with the ".fifo" suffix.
    name         = string
    display_name = optional(string, null)

    # FIFO. fifo_throughput_scope is "Topic" or "MessageGroup" (high throughput).
    fifo_topic                  = optional(bool, false)
    content_based_deduplication = optional(bool, false)
    fifo_throughput_scope       = optional(string, null)
    archive_policy              = optional(string, null)

    # Server-side encryption. Defaults to the AWS-managed key for SNS
    # (alias/aws/sns) unless a customer-managed key ARN/alias is supplied, or
    # encryption is explicitly disabled by setting kms_master_key_id = "".
    kms_master_key_id = optional(string, null)

    # Delivery behaviour / signing / tracing.
    delivery_policy   = optional(string, null)
    signature_version = optional(number, null)
    tracing_config    = optional(string, null)

    # Topic access policy.
    # When policy is set, it is used verbatim and overrides the module-generated
    # cross-account publish policy. allowed_publish_* drive the generated policy.
    policy                      = optional(string, null)
    allowed_publish_account_ids = optional(list(string), [])
    allowed_publish_principals  = optional(list(string), [])

    # Delivery status logging. Callers supply the CloudWatch Logs IAM role ARNs.
    # Sample rate is a percentage (0-100) of successfully delivered messages.
    sqs_success_feedback_role_arn            = optional(string, null)
    sqs_failure_feedback_role_arn            = optional(string, null)
    sqs_success_feedback_sample_rate         = optional(number, null)
    lambda_success_feedback_role_arn         = optional(string, null)
    lambda_failure_feedback_role_arn         = optional(string, null)
    lambda_success_feedback_sample_rate      = optional(number, null)
    http_success_feedback_role_arn           = optional(string, null)
    http_failure_feedback_role_arn           = optional(string, null)
    http_success_feedback_sample_rate        = optional(number, null)
    firehose_success_feedback_role_arn       = optional(string, null)
    firehose_failure_feedback_role_arn       = optional(string, null)
    firehose_success_feedback_sample_rate    = optional(number, null)
    application_success_feedback_role_arn    = optional(string, null)
    application_failure_feedback_role_arn    = optional(string, null)
    application_success_feedback_sample_rate = optional(number, null)

    # Subscriptions nested under the topic, keyed by an arbitrary subscription key.
    subscriptions = optional(map(object({
      protocol                        = string
      endpoint                        = string
      raw_message_delivery            = optional(bool, null)
      filter_policy                   = optional(string, null)
      filter_policy_scope             = optional(string, null)
      redrive_policy                  = optional(string, null)
      delivery_policy                 = optional(string, null)
      replay_policy                   = optional(string, null)
      subscription_role_arn           = optional(string, null)
      confirmation_timeout_in_minutes = optional(number, null)
      endpoint_auto_confirms          = optional(bool, null)
    })), {})
  }))
  nullable = false

  # Topic names must be unique across the map. Two entries with the same name
  # resolve to the same SNS topic, so distinct Terraform addresses would fight
  # over one remote resource.
  validation {
    condition     = length(var.topics) == length(distinct([for _, topic in var.topics : topic.name]))
    error_message = "Each topic name must be unique. Two topics map entries share the same name, which would target the same SNS topic."
  }

  # FIFO topics must be named with the ".fifo" suffix; standard topics must not.
  validation {
    condition = alltrue([
      for _, topic in var.topics :
      topic.fifo_topic ? endswith(topic.name, ".fifo") : !endswith(topic.name, ".fifo")
    ])
    error_message = "FIFO topics (fifo_topic = true) must have a name ending in \".fifo\"; standard topics must not end in \".fifo\"."
  }

  # On a FIFO topic, an SQS subscription endpoint must be a FIFO queue (its ARN
  # ends in ".fifo"). A standard queue subscribed to a FIFO topic silently drops
  # the ordering and deduplication guarantees the FIFO topic exists to provide.
  validation {
    condition = alltrue(flatten([
      for _, topic in var.topics : [
        for _, sub in topic.subscriptions :
        endswith(sub.endpoint, ".fifo")
        if topic.fifo_topic && sub.protocol == "sqs"
      ]
    ]))
    error_message = "An sqs subscription on a FIFO topic must point at a FIFO queue (endpoint ARN ending in \".fifo\"). A standard queue does not preserve FIFO ordering."
  }

  # fifo_throughput_scope, when set, must be a valid value.
  validation {
    condition = alltrue([
      for _, topic in var.topics :
      topic.fifo_throughput_scope == null || contains(["Topic", "MessageGroup"], topic.fifo_throughput_scope)
    ])
    error_message = "fifo_throughput_scope must be either \"Topic\" or \"MessageGroup\"."
  }

  # signature_version, when set, must be 1 (SHA1) or 2 (SHA256).
  validation {
    condition = alltrue([
      for _, topic in var.topics :
      topic.signature_version == null || contains([1, 2], topic.signature_version)
    ])
    error_message = "signature_version must be either 1 (SHA1) or 2 (SHA256)."
  }

  # tracing_config, when set, must be a valid value.
  validation {
    condition = alltrue([
      for _, topic in var.topics :
      topic.tracing_config == null || contains(["PassThrough", "Active"], topic.tracing_config)
    ])
    error_message = "tracing_config must be either \"PassThrough\" or \"Active\"."
  }

  # Delivery status sample rates are percentages (0-100).
  validation {
    condition = alltrue(flatten([
      for _, topic in var.topics : [
        for rate in [
          topic.sqs_success_feedback_sample_rate,
          topic.lambda_success_feedback_sample_rate,
          topic.http_success_feedback_sample_rate,
          topic.firehose_success_feedback_sample_rate,
          topic.application_success_feedback_sample_rate,
        ] : rate == null || (rate >= 0 && rate <= 100)
      ]
    ]))
    error_message = "Delivery status success feedback sample rates must be between 0 and 100."
  }

  # Subscription protocols must be supported by the AWS provider.
  validation {
    condition = alltrue(flatten([
      for _, topic in var.topics : [
        for _, sub in topic.subscriptions :
        contains(["sqs", "lambda", "email", "email-json", "http", "https", "sms", "firehose", "application"], sub.protocol)
      ]
    ]))
    error_message = "Each subscription protocol must be one of: sqs, lambda, email, email-json, http, https, sms, firehose, application."
  }

  # filter_policy_scope, when set, must be a valid value.
  validation {
    condition = alltrue(flatten([
      for _, topic in var.topics : [
        for _, sub in topic.subscriptions :
        sub.filter_policy_scope == null || contains(["MessageAttributes", "MessageBody"], sub.filter_policy_scope)
      ]
    ]))
    error_message = "filter_policy_scope must be either \"MessageAttributes\" or \"MessageBody\"."
  }

  # A firehose subscription requires a subscription_role_arn.
  validation {
    condition = alltrue(flatten([
      for _, topic in var.topics : [
        for _, sub in topic.subscriptions :
        sub.protocol != "firehose" || (sub.subscription_role_arn != null && trimspace(sub.subscription_role_arn) != "")
      ]
    ]))
    error_message = "A subscription with protocol \"firehose\" must set subscription_role_arn."
  }
}

variable "tags" {
  type = object({
    cost-centre      = string
    account-code     = string
    portfolio-id     = string
    project-id       = string
    service-id       = string
    environment-type = string
    owner-business   = string
    budget-holder    = string
    source-repo      = string
    hosting-platform = string
  })
  description = "Mandatory Core Cloud tags applied to all resources: cost-centre, account-code, portfolio-id, project-id, service-id, environment-type, owner-business, budget-holder, source-repo and hosting-platform."
  nullable    = false
}

variable "default_kms_master_key_id" {
  description = "Default KMS key (ARN or alias) used for topic server-side encryption when a topic does not set kms_master_key_id. Set to the AWS-managed SNS key by default. Set a topic's kms_master_key_id to \"\" to disable encryption for that topic."
  type        = string
  default     = "alias/aws/sns"
  nullable    = false
}
