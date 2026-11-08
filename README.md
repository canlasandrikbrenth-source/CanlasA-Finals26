# Ask Tala

Information helpdesk for **Tala Ridge College, a fictional college**. SAM10 final project.
All content is invented. The assistant gives information only and makes no decisions about people.

## Credits

| | |
|---|---|
| Base system | LibreChat v0.8.8 |
| Source | https://github.com/danny-avila/LibreChat |
| Author | Danny Avila and LibreChat contributors |
| Licence | MIT, https://github.com/danny-avila/LibreChat/blob/main/LICENSE |
| Model | Groq free tier, `openai/gpt-oss-120b` by default |

## Layout

| Path | What it is |
|---|---|
| `infra/stack.yaml` | All AWS resources |
| `infra/iam.yaml` | Personal IAM user and MFA-protected admin role |
| `app/` | Docker Compose, LibreChat settings, reskin, gateway |
| `content/` | Knowledge documents, uploaded to S3 |
| `tests/questions.json` | Labelled test questions |
| `ops/` | Install, backup, restore, scheduled tests, fault and fix |
| `scripts/deploy.sh` | Deploys or updates the system from AWS CloudShell |
| `scripts/teardown.sh` | Deletes everything at the end of term |
| `docs/RUN_ORDER.md` | The steps, in order, with the evidence to capture |
| `site/` | Project website skeleton |

## Deploy

From AWS CloudShell, in this repository: `scripts/deploy.sh`
To ship a later change: commit it, then `scripts/deploy.sh update`.

No secret is stored in this repository. They live in Systems Manager Parameter Store under `/asktala/`.

## Automations

| Job | Schedule | Log |
|---|---|---|
| Database backup to S3 | Hourly (`ops/systemd/asktala-backup.timer`) | CloudWatch `/asktala/jobs`, stream `backup` |
| Test questions, pass-rate email | Every 3 hours (`ops/systemd/asktala-eval.timer`) | CloudWatch `/asktala/jobs`, stream `eval` |

Both log `trigger=systemd-timer` when run by the schedule and `trigger=manual` when run by hand.

## Contribution log

| Date | Who | What |
|---|---|---|
| | | |

## AI assistance

Declare here and in the website declaration: which tool, what for, and how you checked its output.
