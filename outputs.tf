output "topic_arns" {
  description = "A map of SNS topic ARNs keyed by topic key."
  value       = { for k, v in aws_sns_topic.this : k => v.arn }
}

output "topic_ids" {
  description = "A map of SNS topic IDs (ARNs) keyed by topic key."
  value       = { for k, v in aws_sns_topic.this : k => v.id }
}

output "topic_names" {
  description = "A map of SNS topic names keyed by topic key."
  value       = { for k, v in aws_sns_topic.this : k => v.name }
}

output "topic_owners" {
  description = "A map of the AWS account ID that owns each topic, keyed by topic key."
  value       = { for k, v in aws_sns_topic.this : k => v.owner }
}

output "subscription_arns" {
  description = "SNS subscription ARNs as a nested map: topic key => subscription key => ARN."
  value = {
    for topic_key, topic in var.topics : topic_key => {
      for sub_key, _ in topic.subscriptions :
      sub_key => aws_sns_topic_subscription.this[jsonencode([topic_key, sub_key])].arn
    }
  }
}
