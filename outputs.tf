output "configuration_set" {
  description = "The ID of the configuration set to set on SES identities for using features of this module"
  value       = aws_sesv2_configuration_set.configuration_set.configuration_set_name
}
