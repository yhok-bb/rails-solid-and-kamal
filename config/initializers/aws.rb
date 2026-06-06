require "aws-sdk-s3"
Aws.config.update(
  request_checksum_calculation: "when_required",
  response_checksum_validation: "when_required"
)
