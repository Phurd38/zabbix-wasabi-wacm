# Legacy: Stats API template

A first version of this project, built on the **Wasabi Stats API**
(`stats.wasabisys.com`), kept for **standalone** Wasabi accounts that are *not*
managed through WACM.

> ⚠️ **Never validated against a live account.** It was written from the public
> documentation and then abandoned when it turned out the author's accounts are
> WACM-managed, for which the Stats API answers `403`. Expect to debug it.
>
> If your accounts are managed in WACM, use the main template instead.

| File | Purpose |
|---|---|
| `wasabi_cloud_storage_by_http.yaml` | Zabbix template |
| `Test-WasabiStatsApi.ps1` | Checks that a key can reach the Stats API |

Authentication is an `Authorization: <AccessKey>:<SecretKey>` header. The key
must be a **root key** or carry the **billing** permission.

Units differ from the WACM template: the Stats API returns bytes directly, so
no multiplier is applied.
