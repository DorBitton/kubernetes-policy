Assignment - Kubernetes policy

You as a member of a platform team are responsible for providing working kubernetes cluster with minimum effort for developers to deploy their applications. Developers write their own applications manifests (like Deployment, Services, Ingresses), but they don’t want to deal with AWS related stuff like zones and high availability. Luckily you as a kubernetes administrator can enforce some of those rules inside the kubernetes cluster on your own.
Please test your solution thoroughly and then publish it in a publicly available git repository. All code, scripts and possibly documentation should be committed into this repository. If manual steps are performed, they should be documented so everybody familiar with the technologies is able to reproduce the steps. Each task should be represented as one or more commits in the repository.

You can use LLM agents to help you but if you do, you must include the full LLM interaction log in the repository (e.g. the jsonl files with session log produced by Claude)
Tasks:
Everything should run on a local machine. No cloud or other external environments should be used.
1. Initial setup, local Kubernetes cluster
Create a local Kubernetes cluster suitable for testing your solution
2. Policy engine setup
Implement kubernetes policies that will make sure pods for each application are balanced as much as possible across all available zones. If possible, consider some edge cases, like pre-existing configuration of scheduling decisions that some applications might already have, or why the the logic might not work correctly for StatefulSets.

