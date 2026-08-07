# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repository _is_ `RT-Extension-AwayMode`, a Perl plugin for **Request Tracker (RT) 6.0.3** that
auto-reassigns tickets away from users on holiday. It's configured with three custom subagents
(`.claude/agents/`) specialized for RT development.

## Subagents

Three domain-specific agents are defined under `.claude/agents/`. Prefer delegating RT-related
questions to the matching agent instead of answering from general knowledge — RT's behavior is
version-specific and these agents are built to verify against primary sources. Note: these custom
agent types are only exposed to the Agent tool outside of plan mode; while planning, use
`general-purpose` agents following the same methodology described below instead.

- **rt-docs** — Answers questions about RT's REST API, configuration, installation/upgrade steps,
  admin features, permissions, and customization (scrips, templates, custom fields, workflows) by
  fetching and citing the official docs at <https://docs.bestpractical.com/rt/6.0.3/>. Use for "how
  does RT do X" questions.
- **rt-source** — Answers questions that require reading actual RT source code (exact module
  behavior, permission/scrip/API implementation, config defaults, class hierarchies). Maintains a
  persistent clone at `~/.cache/rt-source/rt`, checked out to tag `rt-6.0.3` by default. Use when
  `rt-docs` isn't precise enough or the question is really "what does the code do". This clone is
  also useful directly for `perl -I ~/.cache/rt-source/rt/lib -c` syntax checks against real RT
  base classes (`RT::Condition`, `RT::Action`, ...) without a full RT install.
- **rt-extensions** — Finds reference implementations from official Best Practical RT extensions
  (CPAN author `BPS`, packages named `RT-Extension-*`). Caches downloaded extensions under
  `~/.cache/rt-extensions/`. Use for "how would I implement X" questions (e.g. a custom scrip,
  REST2 endpoint, lifecycle hook, custom field type) by finding how official extensions solve the
  same problem.

All three agents pin to RT 6.0.3 by default for consistency; if the user asks about a different
version, tell the relevant agent explicitly.

## RT-Extension-AwayMode

A user can flag themselves "away/holiday" (optionally scoped to a start/end date) on their own
Preferences page. While that flag is active, any new reply (Correspond transaction) or comment
(Comment transaction — `rt-mailgate --action comment` records incoming mail that way) on a ticket
they own gets reassigned to Nobody with an internal comment — unowned tickets are visible to the
whole queue/team, so nothing sits stuck on someone's holiday. Full description and setup steps are
in `README` (generated from the POD in `lib/RT/Extension/AwayMode.pm` — edit the POD, not the
README, then regenerate with `pod2text lib/RT/Extension/AwayMode.pm README`).

### Commands

Run from the repo root:

- `perl -c lib/RT/Extension/AwayMode.pm` — the main module has no RT dependency and checks
  standalone.
- `perl -I ~/.cache/rt-source/rt/lib -c lib/RT/Condition/OwnerAway.pm` and same for
  `lib/RT/Action/OwnerAwayReassign.pm` — these `use base 'RT::Condition'`/`'RT::Action'`, so they
  need RT's lib on `@INC` to syntax-check; the cached clone above works for this.
- `prove -l t/` — runs the pure away-window boundary-logic and transaction-type-filter tests
  (no RT/DB required).
- `perl -e 'package RT::Handle; our (@ScripConditions, @ScripActions, @Scrips); do "./etc/initialdata" or die $@;'`
  — confirms `etc/initialdata` parses (it's executed via `do`, not `require`, so it deliberately has
  no `use strict`, matching RT core's own `etc/initialdata`).
- `perl Makefile.PL` — bundled `inc/` (Module::Install + RTx) is vendored so this runs, but RTx
  needs a _fully installed_ RT (a generated `RT_Config.pm` defining `$RT::LocalPath`) to locate
  itself — a bare source checkout like `~/.cache/rt-source/rt` isn't enough. This step can only be
  completed on a real RT 6.0.3 host.
- Mason files (`html/Prefs/AwayMode.html`, the `PrivilegedMainNav` callback) can't be executed
  standalone; verify by structural comparison against the RT core/BPS extension patterns they're
  modeled on (see file-level comments/POD) or by testing on a live instance.

### Releasing to CPAN

`perl Makefile.PL` only writes a `Makefile` (no `META.yml`/`MANIFEST`) unless it runs in
Module::Install's "admin" mode, which requires the _system_ (non-vendored) `Module::Install` and
`Module::Install::RTx` packages to be installed — `cpanm Module::Install Module::Install::RTx`. In
admin mode it also refreshes the vendored `inc/` bundle from whatever Module::Install/RTx version
is installed system-wide, which is intentional (that's how `inc/` gets upgraded) but means an
admin-mode run can change `inc/**` — review that diff like any other dependency bump.

Release steps, from repo root with RT fully installed (e.g. `RTHOME=/rt-6.0.3`):

1. `perl Makefile.PL` (with `RTHOME` set) — regenerates `Makefile`, `MYMETA.*`, `META.yml`, and
   `inc/`.
2. `pod2text lib/RT/Extension/AwayMode.pm README` — Module::Install::RTx's own `readme_from` call
   (triggered as a side effect of step 1) renders `C<...>` POD codes without quotes, which doesn't
   match this repo's plain `pod2text` convention; re-run `pod2text` after step 1 to keep `README`
   consistent.
3. `make manifest` — regenerates `MANIFEST` from the current file set (respects `MANIFEST.SKIP`).
4. `make dist` — builds `RT-Extension-AwayMode-<version>.tar.gz`.
5. Sanity-check before upload: `tar tzf RT-Extension-AwayMode-*.tar.gz | sort` (no `.git`,
   `.github`, `.claude`, `CLAUDE.md`, or `MYMETA.*` should be present — `MANIFEST.SKIP` excludes
   them), and validate `META.yml` with `CPAN::Meta->load_file('META.yml')` /
   `CPAN::Meta::Validator`.

`Makefile`, `MYMETA.*`, `META.*`, and the built `.tar.gz` are gitignored — they're per-release
build output, not checked in. `MANIFEST` and `inc/` _are_ checked in. There is no GPG signing
(`sign;` was deliberately dropped from `Makefile.PL` — PAUSE doesn't require signed distributions).

#### Automated publishing (`.github/workflows/publish.yml`)

Publishing a GitHub Release (`release: published`) runs the steps above automatically and uploads
the result to PAUSE via `.github/scripts/publish-to-cpan.sh`. The tag name (minus an optional
leading `v`) must exactly match `$VERSION` in `lib/RT/Extension/AwayMode.pm`, or the workflow fails
before building anything.

A stock GitHub-hosted runner has no RT install, so the build itself doesn't run directly on the
runner — it runs as root inside `docker run firefart/requesttracker:latest` (a published image,
RT 6.0.3 at `/opt/rt`), with the checkout bind-mounted in. That image has no `git`, which is why
`actions/checkout` still happens on the plain runner beforehand rather than via a job-level
`container:`. Uploading uses `cpan-upload` (from `CPAN::Uploader`) with credentials written to a
throwaway `~/.pause` inside the container (never passed on the command line), read from the
`PAUSE_USERNAME`/`PAUSE_PASSWORD` repo secrets.

If `firefart/requesttracker:latest` is rebuilt with a different RT version or base image, re-verify
the release script still works — in particular that `cpanm`-installed packages land somewhere on
`@INC` for the container's default user (they need to land under a system path; a non-root user
whose `cpanm` falls back to a per-user `local::lib` under `$HOME` won't have `Module::Install`'s
admin-mode bootstrap file on `@INC`, which is why the workflow runs the container `--user root`).

### Architecture

- **Storage**: away state is one `RT::Attribute` per user via the core `Preferences`/
  `SetPreferences` API (`RT::User`), not a custom field — mirrors core's own self-service prefs
  pattern (e.g. `share/html/Prefs/QueueList.html` in RT core). Shape:
  `{ Enabled => 0|1, StartDate => 'YYYY-MM-DD'|'', EndDate => 'YYYY-MM-DD'|'' }`.
- **Away-window logic** lives in `lib/RT/Extension/AwayMode.pm` as a pure function
  (`IsAwayForPrefs`) with no RT dependency, wrapped by `IsUserAway($UserObj)` for real use — this
  split is what makes `t/away_window.t` runnable without RT installed. Same split for the
  transaction-type filter: pure `IsHandledTransactionType($type, $configured)` (tested in
  `t/transaction_types.t`), wrapped by `IsHandledTransaction($TxnObj)` which reads config and, for
  comments, the creator's `Privileged` flag (`RT->PrivilegedUsers->HasMember`, no ACL involved).
- **Trigger**: `lib/RT/Condition/OwnerAway.pm` (an `RT::Condition` subclass) is applicable when a
  ticket has a real owner who is currently away; it's registered against
  `ApplicableTransTypes => 'Correspond,Comment'` in `etc/initialdata`. RT filters on that DB column
  (`RT::Scrip` line ~618) *before* loading the condition module, so `$AwayModeTransactionTypes` can
  only narrow that set, never widen it — and existing installs need the one-time
  `SetApplicableTransTypes` tweak documented under UPGRADING in the POD (re-running `make initdb`
  would duplicate the scrip).
- **Config**: `etc/AwayMode_Config.pm` ships the defaults for `$AwayModeTransactionTypes`
  (`['Correspond','Comment']`) and `$AwayModeIgnorePrivilegedComments` (`0`). RT loads
  `*_Config.pm` from plugin `etc/` dirs (`RT::Config::Configs`) *after* `RT_SiteConfig.pm`, and a
  non-site file can't override a site-set option — it only logs a "has been ignored" warning. The
  `unless defined $Foo` guard on each `Set` (same trick as BPS `RT-Extension-AutomaticAssignment`)
  avoids that warning. Config files are `require`d from within `package RT`, so bare `$Foo` in them
  is `$RT::Foo` — which is also what `RT::Config::Set` assigns, so the guard actually sees
  site-config values.
- **Effect**: `lib/RT/Action/OwnerAwayReassign.pm` (an `RT::Action` subclass) reloads the ticket as
  `RT->SystemUser` (to bypass the replying user's ACLs), sets `Owner` to `RT->Nobody`, and adds an
  internal `Comment` (not `Correspond`). Since comments now also match the condition, the loop
  guard is the ordering: `SetOwner(Nobody)` happens *before* the `Comment`, so by the time that
  comment's transaction runs scrips the ticket has no real owner and the condition returns 0. Note
  `RT_System` is created via `_BootstrapCreate` and is *not* in the Privileged group, so
  `$AwayModeIgnorePrivilegedComments` is not what stops the loop. `etc/initialdata` wires condition
  + action into one Scrip.
- **UI**: `html/Prefs/AwayMode.html` is a new self-service page (RT's component-root overlay serves
  it at `/Prefs/AwayMode.html`), modeled on BPS `RT::Extension::Hotkeys`' own `/Prefs/*.html`
  pattern. It's linked into the Settings menu via
  `html/Callbacks/RT-Extension-AwayMode/Elements/Header/PrivilegedMainNav`, which hooks RT core's
  `PrivilegedMainNav` callback point (`lib/RT/Interface/Web/MenuBuilder.pm`) the same way BPS
  `RT::Extension::Hotkeys` hooks its own menu callback.
- **Admin UI**: `html/Admin/Users/AwayMode.html` is the admin-side twin of that page, letting
  anyone with `AdminUsers` set another user's away state (core precedent for an admin page editing
  another user's preference: `share/html/Admin/Users/MyRT.html`). It loads the target
  `RT::User` from the `id` arg with the admin's CurrentUser; `RT::User::SetPreferences` enforces
  `AdminUsers` itself via `CurrentUserCanModify`, and the page re-checks that right up front
  because `/Admin/autohandler` only gates the tree on the coarser `ShowConfigTab`.
- **Shared editor**: both pages render and save through `html/Elements/AwayModeEditor`, a
  two-method (`:show` / `:process`) component modeled on RT core's `/Widgets/SavedSearch` — so the
  stored preference shape and the date parsing live in exactly one place. `:process` is called as
  `my @results = $m->comp('/Elements/AwayModeEditor:process', ...)` and returns result messages.
- **Admin menu tab**: `html/Callbacks/RT-Extension-AwayMode/Elements/Tabs/Privileged` adds the tab
  under the per-user Settings submenu. Note RT 6.0.3 has _no_ per-user equivalent of the
  `PrivilegedQueue` callback that `_BuildAdminPageMenu` fires for queues, so this uses the generic
  `Privileged` callback at the end of `BuildPageNav` instead — it runs after `_BuildAdminPageMenu`,
  so `PageMenu()->child('settings')` already exists. The user id comes from `$DECODED_ARGS->{id}`
  (not the callback's `ARGSRef`, which carries `/Elements/Tabs`' own args, not the request's),
  matching how core's own per-user block finds it.
- **Banner**: `html/Callbacks/RT-Extension-AwayMode/autohandler/Default` hooks the `Default`
  callback on `CallbackPage => '/autohandler'` (fired from `RT::Interface::Web::HandleRequest` in
  `lib/RT/Interface/Web.pm`, right after `$m->notes('SystemWarnings')` is reset to `[]` for the
  request and before the page renders). When the logged-in user is away, it pushes a message onto
  that same notes list, which RT core's own `/Elements/SystemWarnings` (rendered inside
  `/Elements/PageLayout`, reached via `/Elements/Tabs` — included on essentially every page,
  including the front page) then renders as a Bootstrap `alert-warning` banner. This reuses RT's
  existing site-wide warning-banner mechanism rather than inventing a new one.

## Working in this repo

When extending this extension, research via the three subagents before writing code, keep
pure/testable logic separate from RT-dependent modules, and verify against
`~/.cache/rt-source/rt` since a live RT instance usually isn't available in this environment.
