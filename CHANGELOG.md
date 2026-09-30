# Changelog

## 7.0-2

- **Trial accounts**: quota now falls back to `trialQuotaTB` when
  `purchasedStorageTB` is empty. Previously a trial account had no quota
  monitoring at all. Adds *Effective quota*, *Quota source* and
  *Trial days remaining*, with alerts for an approaching or past expiry and for
  accounts with no quota defined.
- **Truncation guard**: the collection cap no longer drops sub-accounts
  silently. New items report the API total, the eligible count and a truncation
  flag, with a trigger. Also adds *Collection duration* and an alert well
  before the 60 s timeout.
- **30-day egress** restored at both account and bucket level, with a
  fair-use trigger on the account.
- **Fleet aggregates** and a bundled **dashboard**.
- **Sub-account movement** alerts: added / disappeared.
- New per-account items: egress and ingress per day, SSO and FTP flags.

## 7.0-1

Initial WACM Connect release.

- Two-level discovery: sub-accounts and buckets.
- Quota usage with 75 / 90 / 100 % thresholds.
- *Deleted but still billed* detection for buckets removed during the 90-day
  retention window.
- Unit conversion validated by cross-checking bucket totals against the
  sub-account total (TB for storage, GB for traffic).

## Before 7.0-1

A Stats API template, kept in [`legacy/`](legacy/). Abandoned because the Stats
API only serves standalone accounts.
