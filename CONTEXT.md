# Fullsend Configuration

This context describes how the Quay organization connects repositories to Fullsend agents.

## Language

**Enabled Repository**:
A repository listed in the organization Fullsend configuration as eligible for agent routing.
_Avoid_: Installed repository, onboarded repository

**Enrolled Repository**:
A repository whose default branch contains the Fullsend entrypoint needed to forward events.
_Avoid_: Enabled repository

**Shim Workflow**:
The repository-local Fullsend entrypoint that forwards GitHub events to the organization dispatcher.
_Avoid_: Agent workflow, dispatch workflow

**Dispatch Workflow**:
The organization-level router that maps an incoming event to a Fullsend stage.
_Avoid_: Shim workflow

**Stage**:
A routed Fullsend work type selected from an event, such as triage, code, review, fix, retro, or prioritize.
_Avoid_: Role, command

**Agent Workflow**:
The organization-level workflow that runs the agent for a selected stage.
_Avoid_: Shim workflow, dispatch workflow

## Relationships

- An **Enabled Repository** may or may not be an **Enrolled Repository**.
- An **Enrolled Repository** has exactly one **Shim Workflow** on its default branch.
- A **Shim Workflow** calls the **Dispatch Workflow**.
- A **Dispatch Workflow** selects zero or one **Stage** for each event.
- A **Stage** is handled by one or more **Agent Workflows**.

## Example dialogue

> **Dev:** "The repository is enabled, so why did `/fs-triage` not run?"
> **Domain expert:** "Enabled only means the org config allows routing. The repository must also be enrolled with a shim workflow on its default branch."

**PR Title Pattern**:
The CI-enforced regex that validates pull request titles before merge. Defined per-repo or per-org; agents must match it or the PR is rejected by CI.
_Avoid_: PR format, title format

**Backport Prefix**:
A `[redhat-X.Y]` prefix on a PR title indicating the PR targets a release branch, not the default branch.
_Avoid_: Branch tag, version prefix

**PROJQUAY**:
The JIRA project key for Quay product issues on `issues.redhat.com`. Used in PR titles and commit messages to link code changes to tracked work.
_Avoid_: Ticket number, issue key (too generic)

**QUAYIO**:
The JIRA project key for Quay.io SaaS-specific issues. Distinct from PROJQUAY, which covers the product.
_Avoid_: Quay ticket

**PR Title Linting**:
CI-enforced PR title validation present on some Quay repos (quay/quay, quay-operator). Repos without the check: quay-konflux-components, enhancements, quay-fbcs, quay-konflux-configs, ai-helpers.
_Avoid_: Title check, commit lint

## Flagged ambiguities

- "does not work" can mean the command did not route, the dispatch workflow failed, or the agent workflow ran but produced no useful issue update.
