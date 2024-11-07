# ---------------------------------------------------------------------------------------------------------------------
# SES DEDICATED AND MANAGED IPs
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sesv2_dedicated_ip_pool" "dedicated_pool" {
  pool_name = "${var.name_prefix}-dedicated"
  scaling_mode = "MANAGED"
}

resource "aws_sesv2_configuration_set" "configuration_set" {
  configuration_set_name = "${var.name_prefix}-dedicated"

  delivery_options {
    sending_pool_name = aws_sesv2_dedicated_ip_pool.dedicated_pool.pool_name
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# SES NOTIFICATIONS TO SQS
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_sns_topic" "sending_reports_topic" {
  name = "${var.name_prefix}-ses-sending-reports"
  display_name = "ses-sending-reports"
}

resource "aws_sesv2_configuration_set_event_destination" "sending_reports" {
  configuration_set_name = aws_sesv2_configuration_set.configuration_set.configuration_set_name
  event_destination_name = "sending-reports"

  event_destination {
    sns_destination {
      topic_arn = aws_sns_topic.sending_reports_topic.arn
    }

    enabled              = true
    matching_event_types = ["REJECT", "BOUNCE", "COMPLAINT", "DELIVERY", "RENDERING_FAILURE", "DELIVERY_DELAY"]
  }
}

module "sqs_sending_reports" {
  source = "terraform-aws-modules/sqs/aws"

  name = "${var.name_prefix}-sending-reports"

  delay_seconds             = 5
  max_message_size          = 2048
  message_retention_seconds = 7200
  receive_wait_time_seconds = 10
}

resource "aws_sqs_queue_policy" "sqs_queue_policy" {
  queue_url = module.sqs_sending_reports.queue_id
  policy    = <<POLICY
{
  "Version": "2012-10-17",
  "Id": "sqspolicy",
  "Statement": [
    {
      "Sid": "First",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "sqs:SendMessage",
      "Resource": "${module.sqs_sending_reports.queue_arn}",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "${aws_sns_topic.sending_reports_topic.arn}"
        }
      }
    }
  ]
}
POLICY
}

resource "aws_sns_topic_subscription" "sending_reports_subscription" {
  topic_arn = aws_sns_topic.sending_reports_topic.arn
  protocol  = "sqs"
  endpoint  = module.sqs_sending_reports.queue_arn
}

# ---------------------------------------------------------------------------------------------------------------------
# SENDING REPORTS DYNAMODB
# ---------------------------------------------------------------------------------------------------------------------

module "dynamodb_table_bounce" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "3.3.0"

  # name of the table
  name = "${var.name_prefix}-ses-sending-reports"

  # key/attributes
  hash_key  = "UserId"
  range_key = "messageId"
  attributes = [
    {
      name = "UserId"
      type = "S",
    },
    {
      name = "messageId"
      type = "S",
    },
    {
      name = "domain"
      type = "S"
    },
    {
      name = "from"
      type = "S"
    },
    {
      name = "eventType"
      type = "S"
    }
  ]

  ttl_attribute_name = "ttl"
  ttl_enabled        = true

  global_secondary_indexes = [
    {
      name               = "ByAgency"
      hash_key           = "from"
      range_key          = "UserId"
      projection_type = "ALL"
    },
    {
      name               = "ByDomain"
      hash_key           = "domain"
      range_key          = "UserId"
      projection_type = "ALL"
    },
    {
      name               = "ByEvent"
      hash_key           = "eventType"
      range_key          = "UserId"
      projection_type = "ALL"
    }
  ]

  # enable encrytion
  server_side_encryption_enabled = true
}