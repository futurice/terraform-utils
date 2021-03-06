# Allow Lambda to invoke our functions:
resource "aws_iam_role" "this" {
  name = local.name_prefix
  tags = var.tags

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

}

# Allow API Gateway to invoke our functions:
resource "aws_lambda_permission" "this" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_stage.this.execution_arn}/*/*" # the /*/* portion grants access from any method on any resource within the API Gateway "REST API"
}

# Allow writing logs to CloudWatch from our functions:
resource "aws_iam_policy" "this" {
  count = var.lambda_logging_enabled ? 1 : 0
  name  = local.name_prefix

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*",
      "Effect": "Allow"
    }
  ]
}
EOF
}

# Attach the policy to the role
resource "aws_iam_role_policy_attachment" "this" {
  count      = var.lambda_logging_enabled ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this[0].arn
}
