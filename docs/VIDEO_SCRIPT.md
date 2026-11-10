# Video script (5 to 8 minutes)

Rehearse this in your own words. Check the screen for passwords, keys and personal details before you record. Open every page and tab first.

| Time | Show on screen | Say |
|---|---|---|
| 0:00 to 0:30 | Website home page | Who you are, and what Ask Tala is: a helpdesk for a fictional college, built by reskinning LibreChat and running it on AWS. |
| 0:30 to 1:30 | Ask Tala | Log in. Ask "Where is the Registrar's office and when is it open?" Then ask "Will I be admitted?" and show that it refuses to decide. Explain that the name, content and colours are yours. |
| 1:30 to 2:30 | Infrastructure page | Follow one question from browser to CloudFront, EC2, gateway, S3 and Parameter Store, and out to Groq. Say why it is one server. |
| 2:30 to 3:30 | CloudWatch dashboard and alarms | Show the graphs and the nine alarms. Point out the disk spike. Show the alarm email at 10:42 PM. |
| 3:30 to 4:30 | Restore evidence | Explain what a backup covers. Show the deleted chat, the restore output of 23 seconds, and the chat coming back. State RPO and RTO. |
| 4:30 to 5:45 | Incident page | Say that you caused the fault. Walk through the timeline: detect in 5 min 30 s, fix in 9 min 8 s. Explain the root cause, and why `docker ps` misled you. Show the prevention test. |
| 5:45 to 6:30 | Parameter Store (names only) and Security table | One control and the risk it addresses. Explain the IAM user gap honestly. |
| 6:30 to 7:15 | Results and Next steps | The honest numbers, including the weak answer, then your top improvement: a check from outside the server. |
| 7:15 to 7:45 | Declaration | Say you used AI assistance and how you checked it. Thank the viewer. |

You must present this yourself. Be ready to explain any part if asked.
