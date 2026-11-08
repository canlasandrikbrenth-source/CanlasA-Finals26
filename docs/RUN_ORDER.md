# Run order

Do these in order. **E-xx** is the evidence ID from Appendix B: capture it at that step and hide any key, password or personal detail first.
Run server commands in **Session Manager**: EC2 console > the `asktala` instance > Connect > Session Manager, then `sudo -i`.

## 0. Before anything (15 min)
1. Email your instructor about an extension and about AI-drafted code (Sections 6.1 and 6.3).
2. Create a free key at console.groq.com. Keep it out of files, chats and screenshots.
3. Sign in to AWS as root. Turn on MFA for root. Pick one region, for example Singapore (`ap-southeast-1`).

## 1. Your own login (15 min)
In CloudShell, still as root, per person:
```
aws cloudformation deploy --stack-name asktala-iam-YOURNAME --template-file iam.yaml \
  --parameter-overrides UserName=YOURNAME --capabilities CAPABILITY_NAMED_IAM
```
(Use CloudShell > Actions > Upload file for `infra/iam.yaml`.)
In IAM, give that user a console password and assign an MFA device. Sign in as the user and use the `SwitchRoleUrl` from the stack outputs.
Stop using root. **E-12**: MFA enabled and IAM user list.

## 2. Repository (10 min)
On your computer, in this folder:
```
git init -b main
git add .
git commit -m "Initial Ask Tala kit"
```
Push to a new GitHub repository. Commit each real change as you go, because the history is marked.
In CloudShell, `git clone` your repository and `cd` into it.

## 3. Deploy (start early; about 25 min, mostly waiting)
```
scripts/deploy.sh
```
Answer the two prompts. **Confirm the "AWS Notification" email straight away.**
You will get an `asktala-backup-missed` email until the first backup has run. That is expected.

Wait about 10 minutes, then in Session Manager:
```
docker ps
docker logs asktala-app --tail 20
curl -s localhost:8080/health
```
Create your login (registration is closed to the public). Use an invented address:
```
docker exec -it asktala-app npm run create-user -- demo@talaridge.example "Demo Student" demo
```
Open the URL from `deploy.sh`. Ask "Where is the Registrar's office?"
**E-01**, **E-02**. **E-05**: a screenshot of plain LibreChat for comparison.
Also capture **E-13** (Parameter Store list, names only) and the `aws ec2 describe-instances` output.

## 4. Local run (WS-A item 1; 20 min, needs Docker Desktop)
```
cd app
cp .env.example .env   # fill the values; openssl rand -hex 32 makes them
docker compose up -d --build
```
Open http://localhost:3080. Local `.env` is git-ignored; never commit it.

## 5. First Well-Architected pass (15 min)
Write notes on the six pillars now, before the fault work. You re-run this after step 9.

## 6. Prove the alarms and logging (30 min)
1. Ask 10 or more real questions so the dashboard has data. **E-06**, **E-07**.
2. **E-09**: CloudWatch > Log groups > `/asktala/gateway`.

## 7. Backup and restore (45 min; do it today)
1. Check a backup exists: `aws s3 ls s3://BUCKET/backups/mongo/` in Session Manager. **E-10**.
2. Start a chat with a memorable question. Run `/opt/asktala/ops/backup.sh`.
3. Delete that chat in the app.
4. `/opt/asktala/ops/restore.sh`, type RESTORE. **E-11**: the before and after counts and `elapsed_seconds`, which is your RTO.
5. Log in and show that the deleted chat is back. **E-11**.
6. Your RPO is at most one hour, the backup interval.

## 8. Automations (start by step 3; needs at least 3 to 6 hours)
Leave them alone. After two unattended runs of each:
```
grep trigger=systemd-timer /var/log/asktala/backup.log /var/log/asktala/eval.log
```
Or use CloudWatch `/asktala/jobs`. **E-14**. Runs labelled `trigger=manual` do not count.
The `eval` line is your quality number: "correct on X of 12". **E-04**. The scoring is keyword matching, so check the answers in the `evaluations/` JSON files in S3 and note its limits.

## 9. Fault (45 min)
Note the time at each step: this gives time to detect and time to fix.
Baseline first, then keep the app open:
```
df -h /
/opt/asktala/ops/fault-disk.sh fill
```
1. Wait for the `asktala-disk-above-85` email. **E-08**: the email with date and time visible.
2. Try the app, and investigate with `df -h`, `du -sh /var/log/* | sort -h`, `docker logs asktala-mongo --tail 20`. **E-15**.
3. Fix: run `/opt/asktala/ops/fault-disk.sh clean`, then `docker ps -a`. Restart any stopped container with `docker start <name>`.
4. Prevent: `/opt/asktala/ops/prevent-disk.sh`
5. Verify the prevention: `/opt/asktala/ops/fault-disk.sh fill 240`, then `df -h /` and `ls -lh /var/log/asktala/`. Then `/opt/asktala/ops/fault-disk.sh clean`.

Say honestly that you caused this fault deliberately. The brief allows it.

## 10. Three test questions (10 min)
Pick from `tests/questions.json`, including one wrong or weak answer if you can find a real one. **E-03**.

## 11. Before and after (30 min)
Pick one measure and two **equal** time windows, and write the dates beside each number (Appendix F). With one day these windows are short: say so. **E-16** includes cost from the Billing console.

## 12. Website, video, submit
Fill `site/`, enable GitHub Pages, record the 5 to 8 minute video and embed it. Sign the declaration, then ZIP the repository including `.git`.
Check every screenshot for keys, passwords and personal data.

## After marking
`scripts/teardown.sh`, revoke the Groq key, and tell your instructor (Section 6.2).
