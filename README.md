# Zabbix template for Wasabi — WACM Connect API

Monitor a whole fleet of Wasabi sub-accounts and their buckets from Zabbix,
through the [WACM Connect API](https://docs.wasabi.com/apidocs/wacm-connect-api-authentication).

Built for MSPs and resellers who manage customer accounts in **WACM**
(Wasabi Account Control Manager) and need capacity, quota and cost visibility
next to the rest of their monitoring.

> 🇫🇷 Une version française de cette documentation est disponible dans
> [LISEZ-MOI.md](LISEZ-MOI.md).

---

## Why not the Stats API?

Wasabi ships several APIs and they are not interchangeable:

| API | Intended for | Auth |
|---|---|---|
| S3 | everyone | AWS Signature V4 |
| IAM / STS | everyone | AWS Signature V4 |
| Stats | **standalone accounts only** | `AccessKey:SecretKey` header |
| Account Control (WACA) | legacy partner API | Primary Partner key |
| **WACM Connect** | **WACM subscribers** | **HTTP Basic** |
| AiR | Wasabi AiR customers | product specific |

If your account is managed in WACM, the Stats API returns `403` no matter which
key you generate. This template targets WACM Connect.

---

## What it collects

One `Script` item calls the API and returns a single JSON document; everything
else is a dependent item. **One API call for the sub-account list, then one per
sub-account** — regardless of how many buckets each holds.

```
wasabi.wacm.get  (Script, 1h)
├── 12 template-level items (inventory, health, aggregates)
├── LLD: sub-account discovery  → 18 item prototypes
└── LLD: bucket discovery       → 13 item prototypes
```

### Per sub-account

Active storage · deleted storage still billed · purchased quota · **effective
quota and its source** (`purchased` / `trial` / `none`) · quota usage % · trial
days remaining · account status · quota type · MFA, SSO and FTP flags · bucket
count · daily egress and ingress · 30-day egress.

### Per bucket

Active and deleted storage · storage written and read · active and deleted
objects · daily egress, ingress and API calls · 30-day egress · region ·
**deleted flag and deletion date** · data freshness.

### Fleet aggregates

Total active storage · total deleted storage · total quota sold · overall quota
usage · deleted-data ratio · 30-day egress. A dashboard ships with the template.

---

## Alerts worth knowing about

Beyond the usual thresholds, the template surfaces things that are easy to pay
for without noticing:

| Alert | What it means |
|---|---|
| **Deleted but still billed** | The bucket is gone, but its contents are still charged under Wasabi's 90-day minimum retention |
| **30d egress exceeds stored volume** | Past Wasabi's fair-use expectation of egress ≤ stored volume |
| **Trial expires in less than N days** | No conversion means the customer's service stops |
| **Sub-account list truncated** | The collection cap was hit: some customers are silently no longer monitored |
| **Collection approaching timeout** | Past 60 s the master item fails and all Wasabi monitoring stops at once |
| **Storage dropped by more than N%** | Mass deletion, a misfiring lifecycle rule, or a compromise |
| **Pending deletion** | The sub-account and all of its data are about to disappear |

---

## Requirements

- **Zabbix 7.0+** — the bundled dashboard uses the 72-column grid
- Outbound HTTPS from the Zabbix server or proxy to `api.wacm.wasabisys.com`
- A WACM Connect API key

### Getting a key

| Key type | Generated from | HTTP Basic username |
|---|---|---|
| User key | My profile → WACM Connect | your WACM login |
| Account key | Account tab (Account Admin role) | the account name |

> The username is **never** the name you gave the key. A user key inherits the
> permissions of the user who created it — including `DELETE /sub-accounts/{id}`.
> Create a dedicated WACM user with the lowest role that still returns
> `/sub-accounts` and `/buckets`, rather than using a personal admin key.

The key is shown once. Lost means regenerate.

---

## Installation

**1. Check the key** (PowerShell, no Zabbix needed):

```powershell
.\tools\Test-WacmConnectApi.ps1 -Username you@example.org -ApiKey YOUR_KEY
```

It lists your sub-accounts and their buckets, and saves the raw responses so you
can compare them with [docs/api-samples/](docs/api-samples/).

**2. Import the template**

*Data collection → Templates → Import* →
`template/wasabi_wacm_connect_by_http.yaml` → tick *Create new*.

**3. Create a host**

No IP, no agent — the Zabbix server does the calling. Add the template
`Wasabi WACM Connect by HTTP` and set two macros:

| Macro | Value |
|---|---|
| `{$WASABI.WACM.USER}` | your WACM login (or account name) |
| `{$WASABI.WACM.KEY}` | your API key — stored as *Secret text* |

**4. Trigger the first collection**

Open the item *Wasabi: Get WACM data* and hit **Execute now**. Discovered items
stay empty until the master item produces a value *after* they exist, so without
this you wait a full cycle.

### Updating an existing installation

Same import screen, tick **Update existing** as well. Zabbix matches objects by
UUID, so existing items are updated and **keep their history**. See
[Building](#building) for how that is guaranteed.

---

## Configuration

| Macro | Default | Purpose |
|---|---|---|
| `{$WASABI.WACM.USER}` | — | HTTP Basic username |
| `{$WASABI.WACM.KEY}` | — | API key (secret text) |
| `{$WASABI.WACM.URL}` | `https://api.wacm.wasabisys.com` | API base URL |
| `{$WASABI.HTTP.PROXY}` | — | Outbound HTTP proxy |
| `{$WASABI.SUBACCOUNT.MAX}` | `50` | Sub-accounts collected per run |
| `{$WASABI.SUBACCOUNT.STATUS}` | — | Status filter, e.g. `PAID_ACCOUNT,ON_TRIAL` |
| `{$WASABI.SUBACCOUNT.INCLUDE_DELETED}` | `false` | Include deleted sub-accounts |
| `{$WASABI.SUBACCOUNT.MATCHES}` / `.NOT_MATCHES` | `.*` | Sub-account discovery filters |
| `{$WASABI.BUCKET.MATCHES}` / `.NOT_MATCHES` | `.*` | Bucket discovery filters |
| `{$WASABI.QUOTA.WARN}` / `.HIGH` / `.CRIT` | `75` / `90` / `100` | Quota thresholds (%) |
| `{$WASABI.TRIAL.DAYS.WARN}` | `7` | Trial expiry warning |
| `{$WASABI.BUCKET.STORAGE.MAX}` | `10T` | Per-bucket size alert, context-aware |
| `{$WASABI.BUCKET.DROP.PCT}` | `20` | Storage drop alert (%) |
| `{$WASABI.DELETED.BILLED.MIN}` | `1G` | Floor for the "deleted but billed" alert |
| `{$WASABI.DATA.MAX_AGE}` | `48h` | Staleness threshold |
| `{$WASABI.MFA.ALERT}` | `1` | Set to `0` to mute the MFA check |
| `{$WASABI.DURATION.MAX}` | `45` | Collection duration alert (s) |

Per-bucket overrides use macro context:

```
{$WASABI.BUCKET.STORAGE.MAX:"customer-veeam-repo"} = 50T
```

**Scaling**: each sub-account costs one extra API call against a 60 s timeout.
Use `{$WASABI.SUBACCOUNT.STATUS}` to skip inactive accounts before reaching the
cap, and watch *Collection duration*.

---

## Things to know

**Data is one day old.** Wasabi produces one utilization record per day. This
template gives you capacity and cost visibility, not liveness. There is no
outage detection and no latency here — that would need S3-side probing.

**Counters are daily totals.** Egress, ingress and API calls hold the day's
total, not a monotonic counter. Never apply *Change per second* to them.

**Units.** The API returns storage in **TB** and traffic in **GB**; the template
converts to bytes using decimal TB (10¹²), matching Wasabi billing. Zabbix then
renders bytes in base 1024, so a 1.51 TB account displays as 1.37 TB. Same
volume, different convention — change the multiplier if you would rather match
the WACM console exactly.

`storageWrote` and `storageRead` are assumed to be TB by analogy; they were zero
in every sample available, so that unit is unverified.

**No nested discovery.** Zabbix cannot discover buckets *within* discovered
sub-accounts, so bucket item keys carry both ids:
`wasabi.bucket.storage.active["{#SUBID}","{#BUCKET}"]`. A consequence is that
every customer lives on a single Zabbix host, which rules out the *Top hosts*
widget for per-customer ranking — use *Honeycomb* with an item pattern, or move
to host prototypes.

---

## Building

The template is generated; do not edit `template/*.yaml` by hand.

```
src/collect.js         the collector, as a real JavaScript file
src/template.src.yaml  the template, with symbolic ids and an @@INJECT@@ marker
src/build.py           inlines the JS, resolves ids to UUIDs, validates
```

```bash
pip install pyyaml
python src/build.py
```

`build.py` reads the UUIDs of the currently published template and reuses them,
so a rebuild only mints UUIDs for genuinely new objects. That is what keeps
`Update existing` from destroying item history. It also validates the result:
UUID uniqueness, trigger references, dashboard item references.

---

## Repository layout

```
template/   the importable Zabbix template
src/        sources and build script
tools/      API test script
docs/       anonymised API samples
legacy/     Stats API template for standalone accounts (unvalidated)
```

---

## Contributing

Issues and pull requests welcome — especially:

- confirmation of the `storageWrote` / `storageRead` units on real data
- invoice endpoints (billing data is exposed by the API but unused here)
- a host-prototype variant, one Zabbix host per sub-account

Please rebuild with `python src/build.py` rather than editing the generated
template, and **never commit real account ids, bucket names, customer names or
API keys**. `docs/api-samples/` exists so you do not have to.

---

## License

[MIT](LICENSE)

Not affiliated with or endorsed by Wasabi Technologies.
