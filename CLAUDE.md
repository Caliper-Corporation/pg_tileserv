# CLAUDE.md

<!-- maptitude-online-workflow:start -->
## Issue tracking (Maptitude Online)

All SaaS work is tracked in one repo, `Caliper-Corporation/maptitude-online`, on the org Project "Maptitude Online". Do not open issues in this code repo. Area labels (`area:frontend`, `area:backend`, ...) say which repo the work belongs to. `MO-123` anywhere in this repo links to tracker issue #123.

Working an issue:

1. Read it: `gh issue view <n> -R Caliper-Corporation/maptitude-online --comments`. If the acceptance criteria are unclear, ask in a comment before coding.
2. Claim it: `gh issue edit <n> -R Caliper-Corporation/maptitude-online --add-assignee @me`
3. Branch from the test branch: `staging` if this repo has one, else `dev`, else `main`. Name it `fix/MO-<n>-short-description` or `feature/MO-<n>-short-description`.
4. Start commit messages with `MO-<n>:` (this replaces the old `BugzID:` prefix).
5. Open a draft PR **into the test branch** early. The PR body **must** contain `Refs Caliper-Corporation/maptitude-online#<n>`.
   Never use `Fixes`, `Closes` or `Resolves`. Testers close issues after verifying, and auto-closed issues get reopened.
6. When the PR is ready, mark it ready for review and comment on the issue with what changed and how to test it.
7. Found a separate problem? File it instead of widening the PR:
   `gh issue create -R Caliper-Corporation/maptitude-online --label "bug,needs-triage,area:<area>" --title "..." --body "..."`

The board moves on its own (workflow `.github/workflows/maptitude-online-sync.yml`):
draft PR → In Progress, PR open → In Review, merged into the test branch → Ready for Test (for saas-frontend and saas-backend that means it is live on https://staging.online.caliper.com). Testers move it to Testing and close it, which sets Done. The release PR from the test branch into `main` adds a `released` label to every issue it ships.

Finding work: `gh issue list -R Caliper-Corporation/maptitude-online --label area:<area> --search "no:assignee sort:created-asc"`
<!-- maptitude-online-workflow:end -->
