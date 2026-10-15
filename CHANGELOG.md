All notable changes to this project will be documented in this file. This will provide a record of all notable module updates with each new release. Semantic versioning (https://semver.org/) must be adhered to for all Core Cloud modules.

eg:

### [2.0.0] 2026-10-14

  * BREAKING: adopt the Core Cloud `cc_tags` tagging convention to conform to `core-cloud-tf-module-template`. The `tags` variable (a 10-key hyphenated object) is replaced by `cc_tags`, an 8-key snake_case object (`cost_centre`, `account_code`, `portfolio_id`, `project_id`, `service_id`, `environment_type`, `owner_business`, `budget_holder`). The module maps these to the hyphenated resource-tag keys via a new `common_tags` local. Consumers must rename `tags` to `cc_tags` and drop the `source-repo`/`hosting-platform` keys.
  * Bound the AWS provider constraint to `~> 6.66` (was `>= 6.66.0`) so an uncontrolled future major cannot be pulled in.
  * Add `CODE_OF_CONDUCT.md` and rename `.github/dependabot.yml` to `.github/dependabot.yaml` to match the template.

### [0.1.0] 2026-10-08

  * Initial tag created for Core Cloud SNS Terraform module. Supports standard and FIFO topics with KMS server-side encryption, nested subscriptions (SQS, Lambda, email and others), cross-account publish topic policies (convenience inputs with a raw policy override), and per-protocol delivery status logging.
  * Interface notes for this first release:
    * Subscriptions are keyed internally per topic and subscription key (the module uses `jsonencode([topic_key, subscription_key])` so keys never collide). This is the initial contract; there is no earlier released keying to migrate from.
    * The `subscription_arns` output is a nested map of `topic_key => subscription_key => ARN`. The other outputs (`topic_arns`, `topic_ids`, `topic_names`, `topic_owners`) are flat maps keyed by topic key.
    * SNS FIFO topics deliver to Amazon SQS only; the module rejects all other direct subscription protocols on FIFO topics (fan out to Lambda or Firehose via an intermediate SQS queue).
