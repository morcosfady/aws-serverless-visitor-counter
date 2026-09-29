# Serverless Visitor Counter (AWS + Terraform)

A live visitor counter for my portfolio, built on AWS serverless with Terraform.

```
Portfolio (browser) -> API Gateway (HTTP API) -> Lambda (Python) -> DynamoDB
```

## Services

| Service | Role |
|---------|------|
| API Gateway (HTTP API) | Public `GET /count` endpoint, CORS locked to my portfolio, throttled |
| Lambda (Python 3.12) | Atomically adds +1 and returns the new count |
| DynamoDB (on-demand) | Stores the counter, encrypted at rest |
| CloudWatch Logs | Lambda logs, 7-day retention |
| IAM | Least-privilege role for Lambda |

## Security

- **Least privilege:** Lambda can only call `dynamodb:UpdateItem` on one table, and write its own logs
- **CORS:** only `https://morcosfady.github.io` can call the API from a browser
- **Throttling:** 5 requests/sec (burst 10) to block abuse and surprise bills
- **Encryption:** DynamoDB server-side encryption enabled

## Cost

About $0 at portfolio traffic. Lambda and DynamoDB fall within AWS always-free limits for this usage, the HTTP API costs fractions of a cent per thousand calls, and logs expire after 7 days.

## Design decisions

- **HTTP API over REST API:** cheaper and simpler, enough for one GET route
- **Atomic `ADD` update:** no read-then-write race condition when two visitors arrive at once
- **Terraform + `archive_file`:** the Lambda zip is built and deployed in one `terraform apply`

## Observability and cost guardrails

| What | Details |
|------|---------|
| **CloudWatch dashboard** | Requests, 4xx/5xx, p50/p90 latency, Lambda invocations/errors/throttles/duration, DynamoDB writes, alarm status |
| **4 alarms -> SNS email** | Lambda errors, API 5xx, p90 latency > 1s for 10 min, Lambda throttles (with recovery "OK" emails) |
| **AWS Budget (as code)** | $5/month guardrail: email at 20% actual spend and at 100% forecasted |

All within AWS always-free limits. Alarm notifications are tested with `aws cloudwatch set-alarm-state`.

## CI/CD

Every change is deployed by **GitHub Actions** using **OIDC** (temporary AWS credentials, no stored keys):

- **Pull request:** format check, validate, `terraform plan`
- **Push to main:** plan, `terraform apply`, then a smoke test that calls the live API

State lives in a versioned, encrypted S3 bucket with DynamoDB locking. The deploy role can only manage this project's own resources. See [aws-cicd-oidc-bootstrap](https://github.com/morcosfady/aws-cicd-oidc-bootstrap).

## Usage

```bash
terraform init
terraform apply
# test: open the api_url output in a browser
terraform destroy   # clean up
```
