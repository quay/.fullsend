# Fullsend Configuration

This context describes how the Quay organization connects repositories to
Fullsend agents and names Quay-local Fullsend customizations.

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

**Konflux Assessment**:
An advisory Red Hat Konflux CI diagnosis produced inside the Review Stage for Quay component PRs.
_Avoid_: CI triage, Konflux triage

## Relationships

- An **Enabled Repository** may or may not be an **Enrolled Repository**.
- An **Enrolled Repository** has exactly one **Shim Workflow** on its default branch.
- A **Shim Workflow** calls the **Dispatch Workflow**.
- A **Dispatch Workflow** selects zero or one **Stage** for each event.
- A **Stage** is handled by one or more **Agent Workflows**.
- A **Konflux Assessment** is part of the Review Stage output and is not a separate Stage.

## Example dialogue

> **Dev:** "The repository is enabled, so why did `/fs-triage` not run?"
> **Domain expert:** "Enabled only means the org config allows routing. The repository must also be enrolled with a shim workflow on its default branch."

> **Dev:** "Should the Konflux failure go through the Triage Stage?"
> **Domain expert:** "No. The Review Stage can include a Konflux Assessment, but no new Stage is routed."

## Flagged ambiguities

- "does not work" can mean the command did not route, the dispatch workflow failed, or the agent workflow ran but produced no useful issue update.
- "triage" can mean the Fullsend **Triage Stage** or generic CI diagnosis; resolved: use **Konflux Assessment** for the review-time CI diagnosis.
